#!/usr/bin/env bash
set -euo pipefail

DURATION="${DURATION:-30s}"
THREADS="${THREADS:-10}"
CONNECTIONS="${CONNECTIONS:-100}"
SIZE="${SIZE:-1024}"
OPS_LIST="${OPS_LIST:-1 5 10}"

run_bench() {
    local base_url="$1"
    local label="$2"

    docker compose run --rm --no-deps \
        -e DURATION="$DURATION" \
        -e THREADS="$THREADS" \
        -e CONNECTIONS="$CONNECTIONS" \
        -e SIZE="$SIZE" \
        -e OPS_LIST="$OPS_LIST" \
        bench bash /scripts/runtime-one.sh "$base_url" "$label"
}

printf 'RoadRunner vs FrankenPHP: clean Laravel runtime + cache-read comparison\n'
printf 'cpu=%s memory=%s rr_workers=%s frankenphp_workers=%s\n' \
    "${APP_CPUS:-4.0}" "${APP_MEMORY:-1g}" "${RR_WORKERS:-4}" "${FRANKENPHP_WORKERS:-4}"
printf 'threads=%s connections=%s duration=%s size=%sB cache_ops="%s"\n\n' \
    "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZE" "$OPS_LIST"

docker compose stop app frankenphp >/dev/null 2>&1 || true
docker compose up -d redis >/dev/null

printf '============================================================\n'
printf 'RoadRunner: 4 PHP worker processes + tiered L1/L2 cache\n'
printf '============================================================\n'
docker compose up -d --force-recreate app
printf '\nVersions:\n'
docker compose exec -T app sh -lc 'php -v | head -n1; rr --version; php artisan --version; composer show laravel/octane predis/predis 2>/dev/null | grep -E "^(name|versions)" || true'
run_bench 'http://app:8080' 'RoadRunner + tiered cache'
docker compose stop app >/dev/null

printf '\n============================================================\n'
printf 'FrankenPHP: 4 PHP worker threads + direct Predis cache\n'
printf '============================================================\n'
docker compose up -d --force-recreate frankenphp
printf '\nVersions:\n'
docker compose exec -T frankenphp sh -lc 'php -v | head -n1; frankenphp build-info 2>/dev/null | grep -m1 -E "frankenphp.*v[0-9]" || true; php artisan --version; composer show laravel/octane predis/predis 2>/dev/null | grep -E "^(name|versions)" || true'
run_bench 'http://frankenphp:8080' 'FrankenPHP + Predis cache'

# Safe cleanup: /bench/cleanup deletes only the explicit benchmark key list.
docker compose exec -T frankenphp curl -fsS http://127.0.0.1:8080/bench/cleanup >/dev/null || true
docker compose stop frankenphp >/dev/null

printf '\nComparison complete. Both application runtimes are stopped; Redis service is left running.\n'
