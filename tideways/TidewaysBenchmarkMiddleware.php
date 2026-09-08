<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Throwable;

final class TidewaysBenchmarkMiddleware
{
    public function handle(Request $request, Closure $next): mixed
    {
        if (!class_exists(\Tideways\Profiler::class)) {
            return $next($request);
        }

        $sampleRate = (int) ($_SERVER['TIDEWAYS_BENCH_SAMPLE_RATE'] ?? getenv('TIDEWAYS_BENCH_SAMPLE_RATE') ?: 0);

        \Tideways\Profiler::start([
            'service' => 'benchmark',
            'sample_rate' => $sampleRate,
        ]);

        \Tideways\Profiler::setCustomVariable('http.host', $request->getHttpHost());
        \Tideways\Profiler::setCustomVariable('http.method', $request->getMethod());
        \Tideways\Profiler::setCustomVariable('http.url', $request->getPathInfo());

        if (method_exists(\Tideways\Profiler::class, 'markAsWebTransaction')) {
            \Tideways\Profiler::markAsWebTransaction();
        }

        try {
            return $next($request);
        } catch (Throwable $e) {
            \Tideways\Profiler::logException($e);
            throw $e;
        } finally {
            \Tideways\Profiler::stop();
        }
    }
}
