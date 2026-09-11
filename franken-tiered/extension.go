package frankentiered

/*
#include <Zend/zend_types.h>
#include "extension.h"
*/
import "C"

import (
	"context"
	"errors"
	"hash/fnv"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/dunglas/frankenphp"
	"github.com/redis/go-redis/v9"
)

func init() {
	frankenphp.RegisterExtension(unsafe.Pointer(&C.franken_tiered_module_entry))
}

type config struct {
	addrs        []string
	username     string
	password     string
	db           int
	l1TTL        time.Duration
	queueSize    int
	writers      int
	poolSize     int
	minIdleConns int
	dialTimeout  time.Duration
	readTimeout  time.Duration
	writeTimeout time.Duration
}

type entry struct {
	value     []byte
	expiresAt time.Time
}

type writeOp struct {
	key       string
	value     []byte
	expiresAt time.Time
	persist   bool
}

type driver struct {
	cfg   config
	redis redis.UniversalClient

	mu      sync.RWMutex
	entries map[string]entry
	queues  []chan writeOp
}

var global struct {
	once sync.Once
	drv  *driver
}

func getDriver() *driver {
	global.once.Do(func() {
		cfg := loadConfig()
		client := redis.NewUniversalClient(&redis.UniversalOptions{
			Addrs:        cfg.addrs,
			Username:     cfg.username,
			Password:     cfg.password,
			DB:           cfg.db,
			DialTimeout:  cfg.dialTimeout,
			ReadTimeout:  cfg.readTimeout,
			WriteTimeout: cfg.writeTimeout,
			PoolSize:     cfg.poolSize,
			MinIdleConns: cfg.minIdleConns,
		})

		queuePerWriter := cfg.queueSize / cfg.writers
		if queuePerWriter < 1 {
			queuePerWriter = 1
		}

		d := &driver{
			cfg:     cfg,
			redis:   client,
			entries: make(map[string]entry),
			queues:  make([]chan writeOp, cfg.writers),
		}

		for i := range d.queues {
			d.queues[i] = make(chan writeOp, queuePerWriter)
			go d.writer(d.queues[i])
		}

		global.drv = d
	})

	return global.drv
}

func loadConfig() config {
	host := envString("REDIS_HOST", "redis")
	port := envString("REDIS_PORT", "6379")

	return config{
		addrs:        []string{host + ":" + port},
		username:     os.Getenv("REDIS_USERNAME"),
		password:     os.Getenv("REDIS_PASSWORD"),
		db:           envInt("REDIS_DB", 0),
		l1TTL:        envDuration("FRANKEN_TIERED_L1_TTL", 30*time.Second),
		queueSize:    envInt("FRANKEN_TIERED_QUEUE_SIZE", 10000),
		writers:      max(1, envInt("FRANKEN_TIERED_WRITERS", 4)),
		poolSize:     envInt("FRANKEN_TIERED_POOL_SIZE", 32),
		minIdleConns: envInt("FRANKEN_TIERED_MIN_IDLE_CONNS", 4),
		dialTimeout:  envDuration("FRANKEN_TIERED_DIAL_TIMEOUT", 5*time.Second),
		readTimeout:  envDuration("FRANKEN_TIERED_READ_TIMEOUT", 3*time.Second),
		writeTimeout: envDuration("FRANKEN_TIERED_WRITE_TIMEOUT", 3*time.Second),
	}
}

func envString(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func envInt(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		return fallback
	}
	return parsed
}

func envDuration(key string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

func cloneBytes(value []byte) []byte {
	if value == nil {
		return nil
	}
	out := make([]byte, len(value))
	copy(out, value)
	return out
}

func (d *driver) getL1(key string) ([]byte, bool) {
	d.mu.RLock()
	item, ok := d.entries[key]
	d.mu.RUnlock()
	if !ok {
		return nil, false
	}

	if !item.expiresAt.IsZero() && time.Now().After(item.expiresAt) {
		d.mu.Lock()
		delete(d.entries, key)
		d.mu.Unlock()
		return nil, false
	}

	return cloneBytes(item.value), true
}

func (d *driver) setL1(key string, value []byte, expiresAt time.Time) {
	d.mu.Lock()
	d.entries[key] = entry{value: cloneBytes(value), expiresAt: expiresAt}
	d.mu.Unlock()
}

func (d *driver) get(key string) ([]byte, bool, error) {
	if value, ok := d.getL1(key); ok {
		return value, true, nil
	}

	ctx := context.Background()
	value, err := d.redis.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}

	expiresAt := time.Now().Add(d.cfg.l1TTL)
	if ttl, ttlErr := d.redis.PTTL(ctx, key).Result(); ttlErr == nil && ttl > 0 && ttl < d.cfg.l1TTL {
		expiresAt = time.Now().Add(ttl)
	}

	d.setL1(key, value, expiresAt)
	return cloneBytes(value), true, nil
}

func (d *driver) put(key string, value []byte, seconds int64) error {
	now := time.Now()
	persist := seconds <= 0
	redisExpiresAt := time.Time{}
	l1ExpiresAt := now.Add(d.cfg.l1TTL)

	if !persist {
		redisExpiresAt = now.Add(time.Duration(seconds) * time.Second)
		if redisExpiresAt.Before(l1ExpiresAt) {
			l1ExpiresAt = redisExpiresAt
		}
	}

	d.setL1(key, value, l1ExpiresAt)
	op := writeOp{key: key, value: cloneBytes(value), expiresAt: redisExpiresAt, persist: persist}
	queue := d.queues[d.shard(key)]

	select {
	case queue <- op:
		return nil
	default:
		// Reliability-first fallback: if a shard queue is full, pay Redis latency
		// instead of losing the cache write.
		return d.writeRedis(op)
	}
}

func (d *driver) forget(key string) error {
	d.mu.Lock()
	delete(d.entries, key)
	d.mu.Unlock()
	return d.redis.Del(context.Background(), key).Err()
}

func (d *driver) touch(key string, seconds int64) error {
	if seconds <= 0 {
		seconds = 1
	}

	duration := time.Duration(seconds) * time.Second
	if err := d.redis.Expire(context.Background(), key, duration).Err(); err != nil {
		return err
	}

	if value, ok := d.getL1(key); ok {
		expiresAt := time.Now().Add(duration)
		if d.cfg.l1TTL < duration {
			expiresAt = time.Now().Add(d.cfg.l1TTL)
		}
		d.setL1(key, value, expiresAt)
	}

	return nil
}

func (d *driver) shard(key string) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(key))
	return int(h.Sum32() % uint32(len(d.queues)))
}

func (d *driver) writer(queue <-chan writeOp) {
	for op := range queue {
		_ = d.writeRedis(op)
	}
}

func (d *driver) writeRedis(op writeOp) error {
	ctx := context.Background()
	if op.persist {
		return d.redis.Set(ctx, op.key, op.value, 0).Err()
	}

	ttl := time.Until(op.expiresAt)
	if ttl <= 0 {
		ttl = time.Millisecond
	}
	return d.redis.Set(ctx, op.key, op.value, ttl).Err()
}

//export go_franken_tiered_get
func go_franken_tiered_get(key *C.zend_string, status *C.int) *C.zend_string {
	value, found, err := getDriver().get(frankenphp.GoString(unsafe.Pointer(key)))
	if err != nil {
		*status = 2
		return nil
	}
	if !found {
		*status = 1
		return nil
	}

	*status = 0
	return (*C.zend_string)(frankenphp.PHPString(string(value), false))
}

//export go_franken_tiered_put
func go_franken_tiered_put(key *C.zend_string, value *C.zend_string, seconds C.long) C.int {
	err := getDriver().put(
		frankenphp.GoString(unsafe.Pointer(key)),
		[]byte(frankenphp.GoString(unsafe.Pointer(value))),
		int64(seconds),
	)
	if err != nil {
		return 0
	}
	return 1
}

//export go_franken_tiered_forget
func go_franken_tiered_forget(key *C.zend_string) C.int {
	if err := getDriver().forget(frankenphp.GoString(unsafe.Pointer(key))); err != nil {
		return 0
	}
	return 1
}

//export go_franken_tiered_touch
func go_franken_tiered_touch(key *C.zend_string, seconds C.long) C.int {
	if err := getDriver().touch(frankenphp.GoString(unsafe.Pointer(key)), int64(seconds)); err != nil {
		return 0
	}
	return 1
}
