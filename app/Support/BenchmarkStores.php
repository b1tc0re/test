<?php

namespace App\Support;

use Predis\Client;
use Psr\SimpleCache\CacheInterface;
use Spiral\Goridge\RPC\RPC;
use Spiral\RoadRunner\KeyValue\Factory;

final class BenchmarkStores
{
    /** @var array<string, string> */
    private static array $worker = [];

    /** @var array<int, string> */
    private static array $payloads = [];

    private static ?RPC $rpc = null;
    private static ?CacheInterface $roadRunnerMemory = null;
    private static ?CacheInterface $roadRunnerRedis = null;
    private static ?Client $predis = null;
    private static ?string $workerId = null;

    public static function workerId(): string
    {
        return self::$workerId ??= bin2hex(random_bytes(6));
    }

    public static function payload(int $size): string
    {
        return self::$payloads[$size] ??= str_repeat('x', $size);
    }

    public static function workerGet(string $key): ?string
    {
        return self::$worker[$key] ?? null;
    }

    public static function workerSet(string $key, string $value): void
    {
        self::$worker[$key] = $value;
    }

    public static function roadRunnerMemoryGet(string $key): ?string
    {
        return self::stringValue(self::roadRunnerMemory()->get($key));
    }

    public static function roadRunnerMemorySet(string $key, string $value): void
    {
        self::roadRunnerMemory()->set($key, $value);
    }

    public static function roadRunnerRedisGet(string $key): ?string
    {
        return self::stringValue(self::roadRunnerRedis()->get(self::rrRedisKey($key)));
    }

    public static function roadRunnerRedisSet(string $key, string $value): void
    {
        self::roadRunnerRedis()->set(self::rrRedisKey($key), $value);
    }

    public static function predisGet(string $key): ?string
    {
        return self::stringValue(self::predis()->get(self::predisKey($key)));
    }

    public static function predisSet(string $key, string $value): void
    {
        self::predis()->set(self::predisKey($key), $value);
    }

    public static function rawRedisGet(string $key): ?string
    {
        return self::stringValue(self::predis()->get($key));
    }

    public static function rrRedisRawKey(string $key): string
    {
        return self::rrRedisKey($key);
    }

    public static function predisRawKey(string $key): string
    {
        return self::predisKey($key);
    }

    /** @return array{deleted:int, keys:list<string>} */
    public static function cleanupRedis(): array
    {
        $logicalKeys = [
            'shared-token',
            'payload:64',
            'payload:1024',
            'payload:16384',
            'payload:65536',
        ];

        $keys = [];
        foreach ($logicalKeys as $key) {
            $keys[] = self::rrRedisKey($key);
            $keys[] = self::predisKey($key);
        }

        $deleted = $keys === [] ? 0 : (int) self::predis()->del($keys);

        return ['deleted' => $deleted, 'keys' => $keys];
    }

    private static function roadRunnerMemory(): CacheInterface
    {
        return self::$roadRunnerMemory ??= (new Factory(self::rpc()))->select('memory');
    }

    private static function roadRunnerRedis(): CacheInterface
    {
        return self::$roadRunnerRedis ??= (new Factory(self::rpc()))->select('redis');
    }

    private static function rpc(): RPC
    {
        if (self::$rpc !== null) {
            return self::$rpc;
        }

        $rpcAddress = getenv('RR_RPC') ?: 'tcp://127.0.0.1:6001';

        return self::$rpc = RPC::create($rpcAddress);
    }

    private static function predis(): Client
    {
        if (self::$predis !== null) {
            return self::$predis;
        }

        $parameters = [
            'scheme' => 'tcp',
            'host' => getenv('REDIS_HOST') ?: 'redis',
            'port' => (int) (getenv('REDIS_PORT') ?: 6379),
            'database' => (int) (getenv('REDIS_DB') ?: 0),
        ];

        $username = getenv('REDIS_USERNAME');
        $password = getenv('REDIS_PASSWORD');

        if ($username !== false && $username !== '') {
            $parameters['username'] = $username;
        }

        if ($password !== false && $password !== '') {
            $parameters['password'] = $password;
        }

        return self::$predis = new Client($parameters);
    }

    private static function prefix(): string
    {
        $prefix = trim((string) (getenv('BENCH_KEY_PREFIX') ?: 'rrbench'));
        $prefix = rtrim($prefix, ':');

        return $prefix === '' ? 'rrbench' : $prefix;
    }

    private static function rrRedisKey(string $key): string
    {
        return self::prefix().":rr:{$key}";
    }

    private static function predisKey(string $key): string
    {
        return self::prefix().":predis:{$key}";
    }

    private static function stringValue(mixed $value): ?string
    {
        return $value === null ? null : (string) $value;
    }
}
