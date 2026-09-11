#!/usr/bin/env bash
set -euo pipefail

DURATION="${DURATION:-30s}"
THREADS="${THREADS:-10}"
CONNECTIONS="${CONNECTIONS:-100}"
SIZE="${SIZE:-1024}"
OPS_LIST="${OPS_LIST:-1 5 10}"

run_store() {
    local base_url="$1"
    local store="$2"
    local label="$3"

    docker compose run --rm --no-deps \
        -e DURATION="$DURATION" \
        -e THREADS="$THREADS" \
        -e CONNECTIONS="$CONNECTIONS" \
        -e SIZE="$SIZE" \
        -e OPS_LIST="$OPS_LIST" \
        bench bash /scripts/prod-cache-one.sh "$base_url" "$store" "$label"
}

printf 'Production-like Laravel cache driver comparison\n'
printf 'PHP serialize/unserialize stays in Laravel/PHP for all three paths.\n'
printf 'cpu=%s memory=%s rr_workers=%s frankenphp_workers=%s\n' \
    "${APP_CPUS:-4.0}" "${APP_MEMORY:-1g}" "${RR_WORKERS:-4}" "${FRANKENPHP_WORKERS:-4}"
printf 'threads=%s connections=%s duration=%s target_payload=%sB ops="%s"\n\n' \
    "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZE" "$OPS_LIST"

docker compose stop app frankenphp >/dev/null 2>&1 || true
docker compose up -d redis >/dev/null

printf '============================================================\n'
printf '1) RoadRunner + Laravel RR tiered Store\n'
printf '   PHP array -> serialize() -> Goridge -> Go L1 -> async Redis\n'
printf '============================================================\n'
docker compose up -d --force-recreate app
printf '\nVersions:\n'
docker compose exec -T app sh -lc 'php -v | head -n1; rr --version; php artisan --version'
run_store 'http://app:8080' 'rr-tiered-driver' 'RoadRunner plugin Laravel driver'
docker compose stop app >/dev/null

printf '\n============================================================\n'
printf '2) FrankenPHP + Laravel native Go extension Store\n'
printf '   PHP array -> serialize() -> native PHP/Go call -> Go L1 -> async Redis\n'
printf '============================================================\n'
docker compose up -d --force-recreate frankenphp
printf '\nVersions:\n'
docker compose exec -T frankenphp sh -lc 'php -v | head -n1; frankenphp build-info 2>/dev/null | grep -m1 -E "frankenphp.*v[0-9]" || true; php artisan --version'
run_store 'http://frankenphp:8080' 'franken-native-driver' 'FrankenPHP native extension Laravel driver'

printf '\n============================================================\n'
printf '3) FrankenPHP + standard Laravel RedisStore / Predis\n'
printf '   PHP array -> serialize() -> Predis -> remote Redis\n'
printf '============================================================\n'
run_store 'http://frankenphp:8080' 'predis-driver' 'FrankenPHP standard Laravel RedisStore (Predis)'
docker compose stop frankenphp >/dev/null

printf '\nComparison complete. Both application runtimes are stopped; Redis is left running.\n'
