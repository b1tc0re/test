<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Keepsuit\LaravelOpenTelemetry\Facades\Tracer;
use OpenTelemetry\API\Trace\SpanKind;

class MinimalTelemetryMiddleware
{
    public function handle(Request $request, Closure $next): mixed
    {
        $span = Tracer::newSpan('http.server')
            ->setSpanKind(SpanKind::KIND_SERVER)
            ->start();

        $scope = $span->activate();

        try {
            return $next($request);
        } finally {
            $scope->detach();
            $span->end();
        }
    }
}
