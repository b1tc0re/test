# keepsuit/laravel-opentelemetry Carbon worker-mode benchmark

Minimal reproducible benchmark for the per-request overhead of `Carbon::now()->getTimestamp()` in `WorkerModeManager` when Laravel Octane runs on FrankenPHP.

The benchmark compares two images built from the same pinned stack:

- `carbon`: unmodified `keepsuit/laravel-opentelemetry` v2.2.4.
- `time`: the same package with only the two `Carbon::now()->getTimestamp()` calls in `WorkerModeManager` replaced with `time()`.

No application instrumentation is enabled. OpenTelemetry SDK remains enabled, all exporters use the `null` driver, `flush_after_each_iteration` is disabled, and the default Octane worker-mode detector remains enabled. This isolates the worker-mode callback executed after every Octane request.

## Pinned stack

- FrankenPHP 1.12.7
- PHP 8.4, ZTS, Debian Trixie
- Laravel skeleton 13.10.1
- Laravel Framework 13.30.1
- Laravel Octane 2.19.1
- keepsuit/laravel-opentelemetry 2.2.4

## Requirements

- Linux host
- Docker Engine
- Docker Compose v2
- At least 4 logical CPUs recommended

The server container is limited to 2 CPUs and 512 MiB by default. The wrk client is limited to 1 CPU and 256 MiB. These values are configurable.

## Run

```bash
chmod +x benchmark.sh
./benchmark.sh
```

Defaults:

- 5 measured rounds
- 10 s warmup before every measured run
- 30 s measured duration
- 4 wrk threads
- 100 connections
- alternating order (`carbon -> time`, then `time -> carbon`) to reduce temporal bias

For longer runs:

```bash
ROUNDS=5 DURATION=60s WARMUP=15s ./benchmark.sh
```

Useful overrides:

```bash
SERVER_CPUS=4 \
SERVER_MEMORY=1g \
WRK_CPUS=2 \
THREADS=8 \
CONNECTIONS=100 \
ROUNDS=5 \
DURATION=60s \
./benchmark.sh
```

Raw wrk output and `results.csv` are stored under `results/<timestamp>/`.

## What is intentionally disabled

All Laravel OpenTelemetry application instrumentations are disabled:

- HTTP server/client
- database query
- Redis
- queue
- cache
- event
- view
- Livewire
- console
- Scout

The following remain enabled because they are the subject of the benchmark:

- OpenTelemetry SDK
- `OctaneWorkerModeDetector`
- worker-mode `RequestTerminated` callback

Exporters are configured as `null`, so the test does not measure network, serialization, collector, or backend overhead.

## Verify the only source difference

```bash
docker compose build carbon time

docker compose run --rm --no-deps carbon \
  grep -nE 'Carbon::now\(\)->getTimestamp\(\)|time\(\)' \
  vendor/keepsuit/laravel-opentelemetry/src/WorkerMode/WorkerModeManager.php

docker compose run --rm --no-deps time \
  grep -nE 'Carbon::now\(\)->getTimestamp\(\)|time\(\)' \
  vendor/keepsuit/laravel-opentelemetry/src/WorkerMode/WorkerModeManager.php
```

The `time` image intentionally keeps the unused `use Carbon\Carbon;` import. This makes the runtime source change as small as possible: only the two hot-path calls differ.

## Manual single run

Original package:

```bash
docker compose up -d carbon
docker compose --profile benchmark run --rm --no-deps wrk \
  -t4 -c100 -d60s --latency http://carbon:8000/up
docker compose stop carbon
```

Patched package:

```bash
docker compose up -d time
docker compose --profile benchmark run --rm --no-deps wrk \
  -t4 -c100 -d60s --latency http://time:8000/up
docker compose stop time
```

## Interpretation

The benchmark is not intended to show that Carbon is generally unsuitable for Laravel. It tests one narrow case: constructing a Carbon instance on every request only to obtain an integer Unix timestamp for an interval check in a long-running Octane worker.

If replacing those two calls with `time()` materially increases throughput under otherwise identical conditions, the result points to avoidable hot-path overhead in `WorkerModeManager`.
