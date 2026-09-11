#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://app:8080}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-20}"
DURATION="${DURATION:-10s}"
OPS_LIST="${OPS_LIST:-1 10 100 1000}"
SIZE="${SIZE:-1024}"

run_wrk() {
    local label="$1"
    local path="$2"
    local output rps avg p99

    for _ in $(seq 1 10); do
        curl -fsS "${BASE_URL}${path}" >/dev/null
    done

    output="$(wrk -t"${THREADS}" -c"${CONNECTIONS}" -d"${DURATION}" --latency "${BASE_URL}${path}")"
    rps="$(awk '/Requests\/sec:/ {print $2; exit}' <<<"$output")"
    avg="$(awk '$1 == "Latency" {print $2; exit}' <<<"$output")"
    p99="$(awk '$1 == "99%" {print $2; exit}' <<<"$output")"

    printf '%-34s %14s %14s %14s\n' "$label" "${rps:-?}" "${avg:-?}" "${p99:-?}"
}

for _ in $(seq 1 60); do
    if curl -fsS "${BASE_URL}/bench/plain" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Seed every backend once before the measured requests begin.
curl -fsS "${BASE_URL}/bench/seed-size/${SIZE}" >/dev/null

printf 'Cache operation microbenchmark\n'
printf 'threads=%s connections=%s duration=%s size=%sB ops="%s"\n\n' "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZE" "$OPS_LIST"
printf '%-34s %14s %14s %14s\n' 'ENDPOINT' 'REQ/SEC' 'AVG LAT' 'P99 LAT'
printf '%-34s %14s %14s %14s\n' '----------------------------------' '--------------' '--------------' '--------------'

run_wrk 'plain' '/bench/plain'

for ops in $OPS_LIST; do
    run_wrk "worker ${ops} get/request" "/bench/micro/worker/${ops}/${SIZE}"
    run_wrk "rr memory ${ops} get/request" "/bench/micro/rr-memory/${ops}/${SIZE}"
    run_wrk "rr redis ${ops} get/request" "/bench/micro/rr-redis/${ops}/${SIZE}"
    run_wrk "predis redis ${ops} get/request" "/bench/micro/predis/${ops}/${SIZE}"
done
