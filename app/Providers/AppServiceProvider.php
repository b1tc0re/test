<?php

namespace App\Providers;

use App\Cache\FrankenTieredStore;
use App\Cache\IdentitySerializer;
use App\Cache\RoadRunnerTieredStore;
use Illuminate\Cache\CacheManager;
use Illuminate\Support\ServiceProvider;
use Spiral\Goridge\RPC\RPC;
use Spiral\RoadRunner\KeyValue\Factory;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $prefix = getenv('BENCH_KEY_PREFIX');
        $base = rtrim($prefix !== false && $prefix !== '' ? $prefix : 'rrbench', ':').':prodlike:';

        config()->set('cache.stores.rr-tiered-driver', [
            'driver' => 'rr-tiered-bench',
            'connection' => 'tiered',
            'prefix' => $base.'rr:',
            'events' => false,
        ]);

        config()->set('cache.stores.franken-native-driver', [
            'driver' => 'franken-tiered-bench',
            'prefix' => $base.'franken:',
            'events' => false,
        ]);

        config()->set('cache.stores.predis-driver', [
            'driver' => 'redis',
            'connection' => 'default',
            'lock_connection' => 'default',
            'prefix' => $base.'predis:',
            'events' => false,
        ]);
    }

    public function boot(): void
    {
        /** @var CacheManager $cache */
        $cache = $this->app->make('cache');

        $cache->extend('rr-tiered-bench', function ($app, array $config) use ($cache) {
            $rpcAddress = getenv('RR_RPC');
            $rpc = RPC::create($rpcAddress !== false && $rpcAddress !== '' ? $rpcAddress : 'tcp://127.0.0.1:6001');
            $storage = (new Factory($rpc, new IdentitySerializer()))
                ->select((string) ($config['connection'] ?? 'tiered'));

            return $cache->repository(new RoadRunnerTieredStore(
                $storage,
                (string) ($config['prefix'] ?? ''),
                $app['config']['cache.serializable_classes'] ?? null,
            ), $config);
        });

        $cache->extend('franken-tiered-bench', function ($app, array $config) use ($cache) {
            return $cache->repository(new FrankenTieredStore(
                (string) ($config['prefix'] ?? ''),
                $app['config']['cache.serializable_classes'] ?? null,
            ), $config);
        });
    }
}
