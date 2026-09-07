<?php

use Illuminate\Support\Facades\Route;
use Keepsuit\LaravelOpenTelemetry\WorkerMode\WorkerModeManager;
use Laravel\Octane\Events\RequestTerminated;
use OpenTelemetry\SDK\Sdk;

Route::get('/__benchmark/state', function () {
    return response()->json([
        'laravel_octane' => $_SERVER['LARAVEL_OCTANE'] ?? null,
        'sdk_disabled' => Sdk::isDisabled(),
        'worker_manager_resolved' => app()->resolved(WorkerModeManager::class),
        'request_terminated_listeners' => count(app('events')->getListeners(RequestTerminated::class)),
    ]);
});
