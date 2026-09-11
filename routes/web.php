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
        'rr' => BenchmarkStores::roadRunnerGet($key),
        'redis' => BenchmarkStores::redisGet($key),
    };

    if ($value === null) {
        $value = BenchmarkStores::payload($size);

        match ($backend) {
            'worker' => BenchmarkStores::workerSet($key, $value),
            'rr' => BenchmarkStores::roadRunnerSet($key, $value),
            'redis' => BenchmarkStores::redisSet($key, $value),
        };
    }

    return (string) strlen($value);
};

$write = static function (string $backend, int $size): string {
    $key = "payload:{$size}";
    $value = BenchmarkStores::payload($size);

    match ($backend) {
        'worker' => BenchmarkStores::workerSet($key, $value),
        'rr' => BenchmarkStores::roadRunnerSet($key, $value),
        'redis' => BenchmarkStores::redisSet($key, $value),
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
    BenchmarkStores::roadRunnerSet('shared-token', $token);
    BenchmarkStores::redisSet('shared-token', $token);

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
    'rr_token' => BenchmarkStores::roadRunnerGet('shared-token'),
    'redis_token' => BenchmarkStores::redisGet('shared-token'),
]));

Route::get('/bench/seed-size/{size}', static function (string $size) use ($normalizeSize) {
    $bytes = $normalizeSize($size);
    $key = "payload:{$bytes}";
    $value = BenchmarkStores::payload($bytes);

    BenchmarkStores::workerSet($key, $value);
    BenchmarkStores::roadRunnerSet($key, $value);
    BenchmarkStores::redisSet($key, $value);

    return response()->json(['size' => $bytes]);
});

foreach (['worker', 'rr', 'redis'] as $backend) {
    Route::get("/bench/{$backend}/read/{size}", static function (string $size) use ($backend, $normalizeSize, $read) {
        return response($read($backend, $normalizeSize($size)), 200, ['Content-Type' => 'text/plain']);
    });

    Route::get("/bench/{$backend}/write/{size}", static function (string $size) use ($backend, $normalizeSize, $write) {
        return response($write($backend, $normalizeSize($size)), 200, ['Content-Type' => 'text/plain']);
    });
}
