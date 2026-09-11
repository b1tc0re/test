package tiered

import (
	"context"
	"errors"
	"fmt"
	"hash/fnv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/redis/go-redis/v9"
	kv "github.com/roadrunner-server/api/v4/plugins/v1/kv"
	"go.uber.org/zap"
)

const PluginName = "tiered"

type Logger interface {
	NamedLogger(name string) *zap.Logger
}

type Configurer interface {
	UnmarshalKey(name string, out any) error
	Has(name string) bool
}

type Config struct {
	Addrs         []string      `mapstructure:"addrs" yaml:"addrs"`
	Username      string        `mapstructure:"username" yaml:"username"`
	Password      string        `mapstructure:"password" yaml:"password"`
	DB            int           `mapstructure:"db" yaml:"db"`
	L1TTL         time.Duration `mapstructure:"l1_ttl" yaml:"l1_ttl"`
	QueueSize     int           `mapstructure:"queue_size" yaml:"queue_size"`
	Writers       int           `mapstructure:"writers" yaml:"writers"`
	DialTimeout   time.Duration `mapstructure:"dial_timeout" yaml:"dial_timeout"`
	ReadTimeout   time.Duration `mapstructure:"read_timeout" yaml:"read_timeout"`
	WriteTimeout  time.Duration `mapstructure:"write_timeout" yaml:"write_timeout"`
	PoolSize      int           `mapstructure:"pool_size" yaml:"pool_size"`
	MinIdleConns  int           `mapstructure:"min_idle_conns" yaml:"min_idle_conns"`
	WriteFallback string        `mapstructure:"write_fallback" yaml:"write_fallback"`
}

func (c *Config) defaults() {
	if c.L1TTL <= 0 {
		c.L1TTL = 30 * time.Second
	}
	if c.QueueSize <= 0 {
		c.QueueSize = 10000
	}
	if c.Writers <= 0 {
		c.Writers = 4
	}
	if c.DialTimeout <= 0 {
		c.DialTimeout = 5 * time.Second
	}
	if c.ReadTimeout <= 0 {
		c.ReadTimeout = 3 * time.Second
	}
	if c.WriteTimeout <= 0 {
		c.WriteTimeout = 3 * time.Second
	}
	if c.WriteFallback == "" {
		c.WriteFallback = "block"
	}
}

type Plugin struct {
	cfg Configurer
	log *zap.Logger

	mu     sync.RWMutex
	driver *Driver
}

func (p *Plugin) Init(log Logger, cfg Configurer) error {
	p.log = log.NamedLogger(PluginName)
	p.cfg = cfg
	return nil
}

func (p *Plugin) Name() string { return PluginName }

func (p *Plugin) KvFromConfig(key string) (kv.Storage, error) {
	var cfg Config
	if err := p.cfg.UnmarshalKey(key, &cfg); err != nil {
		return nil, err
	}
	cfg.defaults()
	if len(cfg.Addrs) == 0 {
		return nil, fmt.Errorf("tiered: at least one redis address is required")
	}

	client := redis.NewUniversalClient(&redis.UniversalOptions{
		Addrs:        cfg.Addrs,
		Username:     cfg.Username,
		Password:     cfg.Password,
		DB:           cfg.DB,
		DialTimeout:  cfg.DialTimeout,
		ReadTimeout:  cfg.ReadTimeout,
		WriteTimeout: cfg.WriteTimeout,
		PoolSize:     cfg.PoolSize,
		MinIdleConns: cfg.MinIdleConns,
	})

	ctx, cancel := context.WithTimeout(context.Background(), cfg.DialTimeout)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("tiered: redis ping failed: %w", err)
	}

	perShard := max(1, (cfg.QueueSize+cfg.Writers-1)/cfg.Writers)
	d := &Driver{
		cfg:         cfg,
		log:         p.log,
		redis:       client,
		entries:     make(map[string]entry),
		writeShards: make([]chan writeOp, cfg.Writers),
		stopCh:      make(chan struct{}),
		stopped:     make(chan struct{}),
	}
	for i := 0; i < cfg.Writers; i++ {
		d.writeShards[i] = make(chan writeOp, perShard)
		d.wg.Add(1)
		go d.writer(i)
	}
	go func() {
		d.wg.Wait()
		close(d.stopped)
	}()

	p.mu.Lock()
	p.driver = d
	p.mu.Unlock()

	return d, nil
}

func (p *Plugin) MetricsCollector() []prometheus.Collector {
	p.mu.RLock()
	d := p.driver
	p.mu.RUnlock()
	if d == nil {
		return nil
	}
	return d.metricsCollectors()
}

type entry struct {
	value     []byte
	expiresAt time.Time
}

type writeOp struct {
	key            string
	value          []byte
	redisExpiresAt time.Time
	persist        bool
}

type Driver struct {
	cfg   Config
	log   *zap.Logger
	redis redis.UniversalClient

	mu      sync.RWMutex
	entries map[string]entry

	writeShards []chan writeOp
	wg          sync.WaitGroup
	stopCh      chan struct{}
	stopped     chan struct{}
	once        sync.Once
	closing     atomic.Bool

	l1Hits       atomic.Uint64
	l1Misses     atomic.Uint64
	redisReads   atomic.Uint64
	queued       atomic.Uint64
	completed    atomic.Uint64
	failed       atomic.Uint64
	backpressure atomic.Uint64
	dropped      atomic.Uint64
	queuePeak    atomic.Uint64
}

func (d *Driver) Has(keys ...string) (map[string]bool, error) {
	if len(keys) == 0 {
		return nil, errors.New("tiered: no keys provided")
	}
	result := make(map[string]bool, len(keys))
	for _, key := range keys {
		if strings.TrimSpace(key) == "" {
			return nil, errors.New("tiered: empty key")
		}
		value, err := d.Get(key)
		if err != nil {
			return nil, err
		}
		if value != nil {
			result[key] = true
		}
	}
	return result, nil
}

func (d *Driver) Get(key string) ([]byte, error) {
	if strings.TrimSpace(key) == "" {
		return nil, errors.New("tiered: empty key")
	}
	if value, ok := d.getL1(key); ok {
		d.l1Hits.Add(1)
		return value, nil
	}

	d.l1Misses.Add(1)
	d.redisReads.Add(1)
	ctx := context.Background()
	value, err := d.redis.Get(ctx, key).Bytes()
	if err != nil {
		if errors.Is(err, redis.Nil) {
			return nil, nil
		}
		return nil, err
	}

	l1ExpiresAt := time.Now().Add(d.cfg.L1TTL)
	if ttl, err := d.redis.PTTL(ctx, key).Result(); err == nil && ttl > 0 && ttl < d.cfg.L1TTL {
		l1ExpiresAt = time.Now().Add(ttl)
	}
	d.setL1(key, value, l1ExpiresAt)
	return cloneBytes(value), nil
}

func (d *Driver) MGet(keys ...string) (map[string][]byte, error) {
	if len(keys) == 0 {
		return nil, errors.New("tiered: no keys provided")
	}
	result := make(map[string][]byte, len(keys))
	for _, key := range keys {
		value, err := d.Get(key)
		if err != nil {
			return nil, err
		}
		if value != nil {
			result[key] = value
		}
	}
	return result, nil
}

func (d *Driver) Set(items ...kv.Item) error {
	if len(items) == 0 {
		return errors.New("tiered: no items provided")
	}
	for _, item := range items {
		if item == nil || strings.TrimSpace(item.Key()) == "" {
			return errors.New("tiered: empty item or key")
		}
		l1ExpiresAt, redisExpiresAt, persist, err := parseTimeout(item.Timeout(), d.cfg.L1TTL)
		if err != nil {
			return err
		}
		value := cloneBytes(item.Value())
		d.setL1(item.Key(), value, l1ExpiresAt)
		if err := d.enqueue(writeOp{
			key:            item.Key(),
			value:          value,
			redisExpiresAt: redisExpiresAt,
			persist:        persist,
		}); err != nil {
			return err
		}
	}
	return nil
}

func (d *Driver) MExpire(items ...kv.Item) error {
	if len(items) == 0 {
		return errors.New("tiered: no items provided")
	}
	ctx := context.Background()
	for _, item := range items {
		if item == nil || strings.TrimSpace(item.Key()) == "" || item.Timeout() == "" {
			return errors.New("tiered: invalid expire item")
		}
		deadline, err := time.Parse(time.RFC3339, item.Timeout())
		if err != nil {
			return err
		}
		duration := time.Until(deadline)
		if duration <= 0 {
			duration = time.Millisecond
		}
		if err := d.redis.Expire(ctx, item.Key(), duration).Err(); err != nil {
			return err
		}
		if value, ok := d.getL1(item.Key()); ok {
			d.setL1(item.Key(), value, time.Now().Add(minDuration(duration, d.cfg.L1TTL)))
		}
	}
	return nil
}

func (d *Driver) TTL(keys ...string) (map[string]string, error) {
	if len(keys) == 0 {
		return nil, errors.New("tiered: no keys provided")
	}
	result := make(map[string]string, len(keys))
	ctx := context.Background()
	for _, key := range keys {
		ttl, err := d.redis.PTTL(ctx, key).Result()
		if err != nil {
			return nil, err
		}
		if ttl > 0 {
			result[key] = time.Now().Add(ttl).UTC().Format(time.RFC3339)
		}
	}
	return result, nil
}

func (d *Driver) Clear() error {
	// Intentionally L1-only. Never map generic cache clear to FLUSHDB
	// when the Redis database may be shared with production workloads.
	d.mu.Lock()
	clear(d.entries)
	d.mu.Unlock()
	return nil
}

func (d *Driver) Delete(keys ...string) error {
	if len(keys) == 0 {
		return errors.New("tiered: no keys provided")
	}
	d.mu.Lock()
	for _, key := range keys {
		delete(d.entries, key)
	}
	d.mu.Unlock()
	return d.redis.Del(context.Background(), keys...).Err()
}

func (d *Driver) Stop() {
	d.once.Do(func() {
		d.closing.Store(true)
		close(d.stopCh)
		<-d.stopped
		_ = d.redis.Close()
	})
}

func (d *Driver) getL1(key string) ([]byte, bool) {
	d.mu.RLock()
	e, ok := d.entries[key]
	d.mu.RUnlock()
	if !ok {
		return nil, false
	}
	if !e.expiresAt.IsZero() && time.Now().After(e.expiresAt) {
		d.mu.Lock()
		delete(d.entries, key)
		d.mu.Unlock()
		return nil, false
	}
	return cloneBytes(e.value), true
}

func (d *Driver) setL1(key string, value []byte, expiresAt time.Time) {
	d.mu.Lock()
	d.entries[key] = entry{value: cloneBytes(value), expiresAt: expiresAt}
	d.mu.Unlock()
}

func (d *Driver) enqueue(op writeOp) error {
	if d.closing.Load() {
		return errors.New("tiered: driver is stopping")
	}

	shard := d.shardFor(op.key)
	queue := d.writeShards[shard]
	select {
	case queue <- op:
		d.queued.Add(1)
		d.updateQueuePeak()
		return nil
	default:
		d.backpressure.Add(1)
		if d.cfg.WriteFallback == "drop" {
			d.dropped.Add(1)
			d.log.Warn("tiered write queue full; dropping Redis write", zap.String("key", op.key))
			return nil
		}

		// Blocking preserves per-key FIFO ordering. A synchronous direct Redis
		// fallback could overtake older queued writes for the same key.
		queue <- op
		d.queued.Add(1)
		d.updateQueuePeak()
		return nil
	}
}

func (d *Driver) shardFor(key string) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(key))
	return int(h.Sum32() % uint32(len(d.writeShards)))
}

func (d *Driver) writer(shard int) {
	defer d.wg.Done()
	queue := d.writeShards[shard]
	for {
		select {
		case op := <-queue:
			d.writeRedisLogged(op, "tiered async Redis write failed")
		case <-d.stopCh:
			for {
				select {
				case op := <-queue:
					d.writeRedisLogged(op, "tiered Redis shutdown flush failed")
				default:
					return
				}
			}
		}
	}
}

func (d *Driver) writeRedisLogged(op writeOp, message string) {
	if err := d.writeRedis(op); err != nil {
		d.failed.Add(1)
		d.log.Warn(message, zap.String("key", op.key), zap.Error(err))
		return
	}
	d.completed.Add(1)
}

func (d *Driver) writeRedis(op writeOp) error {
	ctx := context.Background()
	if op.persist {
		return d.redis.Set(ctx, op.key, op.value, 0).Err()
	}
	ttl := time.Until(op.redisExpiresAt)
	if ttl <= 0 {
		ttl = time.Millisecond
	}
	return d.redis.Set(ctx, op.key, op.value, ttl).Err()
}

func (d *Driver) queueDepth() int {
	total := 0
	for _, queue := range d.writeShards {
		total += len(queue)
	}
	return total
}

func (d *Driver) queueCapacity() int {
	total := 0
	for _, queue := range d.writeShards {
		total += cap(queue)
	}
	return total
}

func (d *Driver) updateQueuePeak() {
	depth := uint64(d.queueDepth())
	for {
		peak := d.queuePeak.Load()
		if depth <= peak || d.queuePeak.CompareAndSwap(peak, depth) {
			return
		}
	}
}

func (d *Driver) l1Items() int {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return len(d.entries)
}

func (d *Driver) metricsCollectors() []prometheus.Collector {
	counter := func(name, help string, value *atomic.Uint64) prometheus.Collector {
		return prometheus.NewCounterFunc(prometheus.CounterOpts{Name: name, Help: help}, func() float64 {
			return float64(value.Load())
		})
	}
	return []prometheus.Collector{
		counter("rr_tiered_l1_hits_total", "Tiered cache L1 hits.", &d.l1Hits),
		counter("rr_tiered_l1_misses_total", "Tiered cache L1 misses.", &d.l1Misses),
		counter("rr_tiered_redis_reads_total", "Redis reads caused by L1 misses.", &d.redisReads),
		counter("rr_tiered_writes_queued_total", "Writes accepted into async Redis queues.", &d.queued),
		counter("rr_tiered_writes_completed_total", "Async Redis writes completed successfully.", &d.completed),
		counter("rr_tiered_writes_failed_total", "Async Redis writes that failed.", &d.failed),
		counter("rr_tiered_write_backpressure_total", "Writes that encountered a full shard queue.", &d.backpressure),
		counter("rr_tiered_writes_dropped_total", "Writes dropped because write_fallback=drop.", &d.dropped),
		prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "rr_tiered_write_queue_depth", Help: "Current total async write queue depth."}, func() float64 { return float64(d.queueDepth()) }),
		prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "rr_tiered_write_queue_capacity", Help: "Total async write queue capacity."}, func() float64 { return float64(d.queueCapacity()) }),
		prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "rr_tiered_write_queue_peak", Help: "Peak observed async write queue depth."}, func() float64 { return float64(d.queuePeak.Load()) }),
		prometheus.NewGaugeFunc(prometheus.GaugeOpts{Name: "rr_tiered_l1_items", Help: "Current number of entries in L1."}, func() float64 { return float64(d.l1Items()) }),
	}
}

func parseTimeout(timeout string, l1TTL time.Duration) (l1ExpiresAt time.Time, redisExpiresAt time.Time, persist bool, err error) {
	now := time.Now()
	if timeout == "" {
		return now.Add(l1TTL), time.Time{}, true, nil
	}
	deadline, err := time.Parse(time.RFC3339, timeout)
	if err != nil {
		return time.Time{}, time.Time{}, false, err
	}
	remaining := time.Until(deadline)
	if remaining <= 0 {
		remaining = time.Millisecond
	}
	return now.Add(minDuration(remaining, l1TTL)), deadline, false, nil
}

func minDuration(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}

func cloneBytes(v []byte) []byte {
	if v == nil {
		return nil
	}
	out := make([]byte, len(v))
	copy(out, v)
	return out
}
