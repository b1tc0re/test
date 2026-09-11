<?php

use App\Support\BenchmarkStores;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

$normalizeSize = static function (string $size): int {
    $size = (int) $size;

    abort_unless(in_array($size, [64, 1024, 16384, 65536], true), 404);

    return $size;
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
}
