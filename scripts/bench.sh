#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://app:8080}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
DURATION="${DURATION:-10s}"
SIZES="${SIZES:-1024}"
MODE="${MODE:-all}"

wait_for_app() {
    for _ in $(seq 1 60); do
        if curl -fsS "${BASE_URL}/bench/plain" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    echo "Application is not ready: ${BASE_URL}" >&2
    exit 1
}

run_wrk() {
    local label="$1"
    local path="$2"
    local output rps avg p99

    for _ in $(seq 1 20); do
        curl -fsS "${BASE_URL}${path}" >/dev/null
    done

    output="$(wrk -t"${THREADS}" -c"${CONNECTIONS}" -d"${DURATION}" --latency "${BASE_URL}${path}")"
    rps="$(awk '/Requests\/sec:/ {print $2; exit}' <<<"$output")"
    avg="$(awk '$1 == "Latency" {print $2; exit}' <<<"$output")"
    p99="$(awk '$1 == "99%" {print $2; exit}' <<<"$output")"

    printf '%-30s %14s %14s %14s\n' "$label" "${rps:-?}" "${avg:-?}" "${p99:-?}"
}

wait_for_app

printf 'RoadRunner benchmark\n'
printf 'threads=%s connections=%s duration=%s sizes="%s" mode=%s\n\n' "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZES" "$MODE"
printf '%-30s %14s %14s %14s\n' 'ENDPOINT' 'REQ/SEC' 'AVG LAT' 'P99 LAT'
printf '%-30s %14s %14s %14s\n' '------------------------------' '--------------' '--------------' '--------------'

run_wrk 'plain' '/bench/plain'

for size in $SIZES; do
    curl -fsS "${BASE_URL}/bench/seed-size/${size}" >/dev/null

    run_wrk "worker read ${size}B" "/bench/worker/read/${size}"
    run_wrk "rr memory read ${size}B" "/bench/rr-memory/read/${size}"
    run_wrk "rr redis read ${size}B" "/bench/rr-redis/read/${size}"
    run_wrk "predis redis read ${size}B" "/bench/predis/read/${size}"

    if [[ "$MODE" == "all" || "$MODE" == "write" ]]; then
        run_wrk "worker write ${size}B" "/bench/worker/write/${size}"
        run_wrk "rr memory write ${size}B" "/bench/rr-memory/write/${size}"
        run_wrk "rr redis write ${size}B" "/bench/rr-redis/write/${size}"
        run_wrk "predis redis write ${size}B" "/bench/predis/write/${size}"
    fi
done
