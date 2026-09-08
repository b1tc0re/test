<?php

use Illuminate\Support\Facades\Route;
use Laravel\Octane\Events\RequestTerminated;

Route::get('/_benchmark/state', function () {
    $packageInstalled = class_exists(\Keepsuit\LaravelOpenTelemetry\LaravelOpenTelemetryServiceProvider::class);

    $sdkDisabled = null;
    $providerLoaded = false;
    $workerManagerResolved = false;
    $httpServerEnabled = null;

    if ($packageInstalled) {
        $sdkDisabled = \OpenTelemetry\SDK\Sdk::isDisabled();
        $providerLoaded = app()->getProvider(
            \Keepsuit\LaravelOpenTelemetry\LaravelOpenTelemetryServiceProvider::class
        ) !== null;
        $workerManagerResolved = app()->resolved(
            \Keepsuit\LaravelOpenTelemetry\WorkerMode\WorkerModeManager::class
        );

        $httpConfig = config(
            'opentelemetry.instrumentation.'.\Keepsuit\LaravelOpenTelemetry\Instrumentation\HttpServerInstrumentation::class
        );

        $httpServerEnabled = is_array($httpConfig)
            ? (bool) ($httpConfig['enabled'] ?? true)
            : (bool) $httpConfig;
    }

    return response()->json([
        'laravel_octane' => $_SERVER['LARAVEL_OCTANE'] ?? null,
        'package_installed' => $packageInstalled,
        'provider_loaded' => $providerLoaded,
        'sdk_disabled' => $sdkDisabled,
        'worker_manager_resolved' => $workerManagerResolved,
        'request_terminated_listeners' => count(app('events')->getListeners(RequestTerminated::class)),
        'http_server_enabled' => $httpServerEnabled,
    ]);
});
