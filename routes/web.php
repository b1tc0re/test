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

    abort_unless(in_array($ops, [1, 10, 100, 1000], true), 404);

    return $ops;
};

$read = static function (string $backend, int $size): string {
    $key = "payload:{$size}";
    $value = match ($backend) {
        'worker' => BenchmarkStores::workerGet($key),
        'rr-memory' => BenchmarkStores::roadRunnerMemoryGet($key),
        'rr-redis' => BenchmarkStores::roadRunnerRedisGet($key),
        'predis' => BenchmarkStores::predisGet($key),
    };

    if ($value === null) {
        $value = BenchmarkStores::payload($size);

        match ($backend) {
            'worker' => BenchmarkStores::workerSet($key, $value),
            'rr-memory' => BenchmarkStores::roadRunnerMemorySet($key, $value),
            'rr-redis' => BenchmarkStores::roadRunnerRedisSet($key, $value),
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

Route::get('/bench/pid', static fn () => response()->json([
    'pid' => getmypid(),
    'worker_id' => BenchmarkStores::workerId(),
]));

Route::get('/bench/seed', static function (Request $request) {
    $token = (string) ($request->query('token') ?: bin2hex(random_bytes(8)));

    BenchmarkStores::workerSet('shared-token', $token);
    BenchmarkStores::roadRunnerMemorySet('shared-token', $token);
    BenchmarkStores::roadRunnerRedisSet('shared-token', $token);
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
    'predis_token' => BenchmarkStores::predisGet('shared-token'),
]));

Route::get('/bench/redis-raw', static fn () => response()->json([
    'rr_key' => BenchmarkStores::rrRedisRawKey('shared-token'),
    'rr_raw' => BenchmarkStores::rawRedisGet(BenchmarkStores::rrRedisRawKey('shared-token')),
    'predis_key' => BenchmarkStores::predisRawKey('shared-token'),
    'predis_raw' => BenchmarkStores::rawRedisGet(BenchmarkStores::predisRawKey('shared-token')),
]));

Route::get('/bench/cleanup', static fn () => response()->json(BenchmarkStores::cleanupRedis()));

Route::get('/bench/seed-size/{size}', static function (string $size) use ($normalizeSize) {
    $bytes = $normalizeSize($size);
    $key = "payload:{$bytes}";
    $value = BenchmarkStores::payload($bytes);

    BenchmarkStores::workerSet($key, $value);
    BenchmarkStores::roadRunnerMemorySet($key, $value);
    BenchmarkStores::roadRunnerRedisSet($key, $value);
    BenchmarkStores::predisSet($key, $value);

    return response()->json(['size' => $bytes]);
});

foreach (['worker', 'rr-memory', 'rr-redis', 'predis'] as $backend) {
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
