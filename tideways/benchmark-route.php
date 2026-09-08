<?php

use Illuminate\Support\Facades\Route;

Route::get('/_benchmark/state', function () {
    return response()->json([
        'laravel_octane' => $_SERVER['LARAVEL_OCTANE'] ?? null,
        'tideways_extension' => extension_loaded('tideways'),
        'tideways_profiler_class' => class_exists(\Tideways\Profiler::class),
        'bench_enabled' => filter_var(env('TIDEWAYS_BENCH_ENABLED', false), FILTER_VALIDATE_BOOLEAN),
        'sample_rate' => (int) env('TIDEWAYS_BENCH_SAMPLE_RATE', 0),
        'php_sapi' => PHP_SAPI,
        'php_version' => PHP_VERSION,
    ]);
});
