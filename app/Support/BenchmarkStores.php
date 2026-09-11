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

    private static ?CacheInterface $roadRunner = null;
    private static ?Client $redis = null;
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

    public static function roadRunnerGet(string $key): ?string
    {
        $value = self::roadRunner()->get($key);

        return $value === null ? null : (string) $value;
    }

    public static function roadRunnerSet(string $key, string $value): void
    {
        self::roadRunner()->set($key, $value);
    }

    public static function redisGet(string $key): ?string
    {
        $value = self::redis()->get($key);

        return $value === null ? null : (string) $value;
    }

    public static function redisSet(string $key, string $value): void
    {
        self::redis()->set($key, $value);
    }

    private static function roadRunner(): CacheInterface
    {
        if (self::$roadRunner !== null) {
            return self::$roadRunner;
        }

        $rpcAddress = getenv('RR_RPC') ?: 'tcp://127.0.0.1:6001';
        $rpc = RPC::create($rpcAddress);

        return self::$roadRunner = (new Factory($rpc))->select('memory');
    }

    private static function redis(): Client
    {
        if (self::$redis !== null) {
            return self::$redis;
        }

        return self::$redis = new Client([
            'scheme' => 'tcp',
            'host' => getenv('REDIS_HOST') ?: 'redis',
            'port' => (int) (getenv('REDIS_PORT') ?: 6379),
        ]);
    }
}
