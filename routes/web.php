<?php

use App\Support\BenchmarkStores;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

$normalizeSize = static function (string $size): int {
    $size = (int) $size;

    abort_unless(in_array($size, [64, 1024, 16384, 65536], true), 404);

    return $size;
};

$normalizeOps = static function (string $ops): int {
    $ops = (int) $ops;

    abort_unless(in_array($ops, [1, 5, 10, 100, 1000], true), 404);

    return $ops;
};

$normalizeSlots = static function (string $slots): int {
    $slots = (int) $slots;

    abort_unless(in_array($slots, [64, 256, 1024], true), 404);

    return $slots;
};

$read = static function (string $backend, int $size): string {
    $key = "payload:{$size}";
    $value = match ($backend) {
        'worker' => BenchmarkStores::workerGet($key),
        'rr-memory' => BenchmarkStores::roadRunnerMemoryGet($key),
        'rr-redis' => BenchmarkStores::roadRunnerRedisGet($key),
        'tiered' => BenchmarkStores::tieredGet($key),
        'predis' => BenchmarkStores::predisGet($key),
    };

    if ($value === null) {
        $value = BenchmarkStores::payload($size);

        match ($backend) {
            'worker' => BenchmarkStores::workerSet($key, $value),
            'rr-memory' => BenchmarkStores::roadRunnerMemorySet($key, $value),
            'rr-redis' => BenchmarkStores::roadRunnerRedisSet($key, $value),
            'tiered' => BenchmarkStores::tieredSet($key, $value),
            'predis' => BenchmarkStores::predisSet($key, $value),
        };
    }

    return (string) strlen($value);
};

$write = static function (string $backend, int $size): string {
    $key = "payload:{$size}";
    $value = BenchmarkStores::payload($size);

    match ($backend) {
        'worker' => BenchmarkStores::workerSet($key, $value),
        'rr-memory' => BenchmarkStores::roadRunnerMemorySet($key, $value),
        'rr-redis' => BenchmarkStores::roadRunnerRedisSet($key, $value),
        'tiered' => BenchmarkStores::tieredSet($key, $value),
        'predis' => BenchmarkStores::predisSet($key, $value),
    };

    return 'OK';
};

$microRead = static function (string $backend, int $ops, int $size): string {
    $key = "payload:{$size}";
    $total = 0;

    for ($i = 0; $i < $ops; $i++) {
        $item = match ($backend) {
            'worker' => BenchmarkStores::workerGet($key),
            'rr-memory' => BenchmarkStores::roadRunnerMemoryGet($key),
            'rr-redis' => BenchmarkStores::roadRunnerRedisGet($key),
            'tiered' => BenchmarkStores::tieredGet($key),
            'predis' => BenchmarkStores::predisGet($key),
        };

        if ($item === null && $backend === 'worker') {
            $item = BenchmarkStores::payload($size);
            BenchmarkStores::workerSet($key, $item);
        }

        abort_if($item === null, 500, "Benchmark key is not seeded for {$backend}");
        $total += strlen($item);
    }

    return (string) $total;
};

Route::get('/bench/plain', static fn () => response('OK', 200, ['Content-Type' => 'text/plain']));

Route::get('/bench/runtime/probe', static fn () => response()->json([
    'pid' => getmypid(),
    'worker_id' => BenchmarkStores::workerId(),
    'cache_backend' => BenchmarkStores::runtimeCacheBackend(),
    'sapi' => PHP_SAPI,
    'zts' => (bool) PHP_ZTS,
    'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? null,
]));

Route::get('/bench/runtime/cache/seed/{size}', static function (string $size) use ($normalizeSize) {
    $bytes = $normalizeSize($size);
    BenchmarkStores::runtimeCacheSet("runtime-payload:{$bytes}", BenchmarkStores::payload($bytes));

    return response()->json([
        'size' => $bytes,
        'backend' => BenchmarkStores::runtimeCacheBackend(),
    ]);
});

Route::get('/bench/runtime/cache/read/{ops}/{size}', static function (string $ops, string $size) use ($normalizeOps, $normalizeSize) {
    $count = $normalizeOps($ops);
    $bytes = $normalizeSize($size);
    $key = "runtime-payload:{$bytes}";
    $total = 0;

    for ($i = 0; $i < $count; $i++) {
        $value = BenchmarkStores::runtimeCacheGet($key);
        abort_if($value === null, 500, 'Runtime cache benchmark key is not seeded');
        $total += strlen($value);
    }

    return response((string) $total, 200, ['Content-Type' => 'text/plain']);
});

Route::get('/bench/runtime/cache/write/{size}', static function (string $size) use ($normalizeSize) {
    $bytes = $normalizeSize($size);
    BenchmarkStores::runtimeCacheSet("runtime-payload:{$bytes}", BenchmarkStores::payload($bytes));

    return response('OK', 200, ['Content-Type' => 'text/plain']);
});

Route::get('/bench/pid', static fn () => response()->json([
    'pid' => getmypid(),
    'worker_id' => BenchmarkStores::workerId(),
]));

Route::get('/bench/seed', static function (Request $request) {
    $token = (string) ($request->query('token') ?: bin2hex(random_bytes(8)));

    BenchmarkStores::workerSet('shared-token', $token);
    BenchmarkStores::roadRunnerMemorySet('shared-token', $token);
    BenchmarkStores::roadRunnerRedisSet('shared-token', $token);
    BenchmarkStores::tieredSet('shared-token', $token);
    BenchmarkStores::predisSet('shared-token', $token);

    return response()->json([
        'pid' => getmypid(),
        'worker_id' => BenchmarkStores::workerId(),
        'token' => $token,
    ]);
});

Route::get('/bench/probe', static fn () => response()->json([
    'pid' => getmypid(),
    'worker_id' => BenchmarkStores::workerId(),
    'worker_token' => BenchmarkStores::workerGet('shared-token'),
    'rr_memory_token' => BenchmarkStores::roadRunnerMemoryGet('shared-token'),
    'rr_redis_token' => BenchmarkStores::roadRunnerRedisGet('shared-token'),
    'tiered_token' => BenchmarkStores::tieredGet('shared-token'),
    'predis_token' => BenchmarkStores::predisGet('shared-token'),
]));

Route::get('/bench/redis-raw', static fn () => response()->json([
    'rr_key' => BenchmarkStores::rrRedisRawKey('shared-token'),
    'rr_raw' => BenchmarkStores::rawRedisGet(BenchmarkStores::rrRedisRawKey('shared-token')),
    'tiered_key' => BenchmarkStores::tieredRawKey('shared-token'),
    'tiered_raw' => BenchmarkStores::rawRedisGet(BenchmarkStores::tieredRawKey('shared-token')),
    'predis_key' => BenchmarkStores::predisRawKey('shared-token'),
    'predis_raw' => BenchmarkStores::rawRedisGet(BenchmarkStores::predisRawKey('shared-token')),
]));

Route::get('/bench/cleanup', static fn () => response()->json(BenchmarkStores::cleanupRedis()));

Route::get('/bench/tiered/proof/set', static function (Request $request) {
    $token = (string) ($request->query('token') ?: 'tiered-'.bin2hex(random_bytes(8)));
    $start = hrtime(true);
    BenchmarkStores::tieredSet('tiered-proof', $token);
    $elapsedUs = (hrtime(true) - $start) / 1000;

    return response()->json([
        'token' => $token,
        'set_elapsed_us' => round($elapsedUs, 2),
        'redis_visible_immediately' => BenchmarkStores::rawRedisGet(BenchmarkStores::tieredRawKey('tiered-proof')) !== null,
    ]);
});

Route::get('/bench/tiered/proof/clear-l1', static function () {
    BenchmarkStores::tieredClearL1();

    return response()->json(['cleared' => true]);
});

Route::get('/bench/tiered/proof/get', static function () {
    $start = hrtime(true);
    $value = BenchmarkStores::tieredGet('tiered-proof');
    $elapsedUs = (hrtime(true) - $start) / 1000;

    return response()->json([
        'value' => $value,
        'get_elapsed_us' => round($elapsedUs, 2),
    ]);
});

Route::get('/bench/tiered/writebench/{size}/{slots}', static function (string $size, string $slots) use ($normalizeSize, $normalizeSlots) {
    $bytes = $normalizeSize($size);
    $slotCount = $normalizeSlots($slots);
    $slot = BenchmarkStores::nextWriteBenchSlot($bytes, $slotCount);

    BenchmarkStores::tieredSet("writebench:{$bytes}:{$slot}", BenchmarkStores::payload($bytes));

    return response('OK', 200, ['Content-Type' => 'text/plain']);
});

Route::get('/bench/tiered/writebench-cleanup/{size}/{slots}', static function (string $size, string $slots) use ($normalizeSize, $normalizeSlots) {
    return response()->json(BenchmarkStores::cleanupTieredWriteBench(
        $normalizeSize($size),
        $normalizeSlots($slots),
    ));
});

Route::get('/bench/seed-size/{size}', static function (string $size) use ($normalizeSize) {
    $bytes = $normalizeSize($size);
    $key = "payload:{$bytes}";
    $value = BenchmarkStores::payload($bytes);

    BenchmarkStores::workerSet($key, $value);
    BenchmarkStores::roadRunnerMemorySet($key, $value);
    BenchmarkStores::roadRunnerRedisSet($key, $value);
    BenchmarkStores::tieredSet($key, $value);
    BenchmarkStores::predisSet($key, $value);

    return response()->json(['size' => $bytes]);
});

foreach (['worker', 'rr-memory', 'rr-redis', 'tiered', 'predis'] as $backend) {
    Route::get("/bench/{$backend}/read/{size}", static function (string $size) use ($backend, $normalizeSize, $read) {
        return response($read($backend, $normalizeSize($size)), 200, ['Content-Type' => 'text/plain']);
    });

    Route::get("/bench/{$backend}/write/{size}", static function (string $size) use ($backend, $normalizeSize, $write) {
        return response($write($backend, $normalizeSize($size)), 200, ['Content-Type' => 'text/plain']);
    });

    Route::get("/bench/micro/{$backend}/{ops}/{size}", static function (string $ops, string $size) use ($backend, $normalizeOps, $normalizeSize, $microRead) {
        return response(
            $microRead($backend, $normalizeOps($ops), $normalizeSize($size)),
            200,
            ['Content-Type' => 'text/plain'],
        );
    });
}
