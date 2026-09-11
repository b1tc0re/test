#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:?base URL required}"
STORE="${2:?cache store required}"
LABEL="${3:?label required}"
THREADS="${THREADS:-10}"
CONNECTIONS="${CONNECTIONS:-100}"
DURATION="${DURATION:-30s}"
SIZE="${SIZE:-1024}"
OPS_LIST="${OPS_LIST:-1 5 10}"

wait_for_runtime() {
    for _ in $(seq 1 60); do
        if curl -fsS "${BASE_URL}/bench/plain" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    echo "Runtime is not ready: ${BASE_URL}" >&2
    exit 1
}

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

    printf '%-36s %14s %14s %14s\n' "$label" "${rps:-?}" "${avg:-?}" "${p99:-?}"
}

wait_for_runtime

printf '\n%s\n' "$LABEL"
printf 'store=%s threads=%s connections=%s duration=%s target=%sB ops="%s"\n' \
    "$STORE" "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZE" "$OPS_LIST"

printf '\nDriver probe:\n'
curl -fsS "${BASE_URL}/bench/prod-cache/probe/${STORE}" | jq .

printf '\nSeed / serialized payload:\n'
curl -fsS "${BASE_URL}/bench/prod-cache/seed/${STORE}/${SIZE}" | jq .

printf '\n%-36s %14s %14s %14s\n' 'ENDPOINT' 'REQ/SEC' 'AVG LAT' 'P99 LAT'
printf '%-36s %14s %14s %14s\n' '------------------------------------' '--------------' '--------------' '--------------'
run_wrk 'plain Laravel' '/bench/plain'

for ops in $OPS_LIST; do
    run_wrk "Laravel cache read ${ops}/request" "/bench/prod-cache/read/${STORE}/${ops}/${SIZE}"
done

run_wrk 'Laravel cache write 1/request' "/bench/prod-cache/write/${STORE}/${SIZE}"

# Let asynchronous L2 writers drain before deleting the exact test key. Then
# delete it twice to avoid a late queued write repopulating it between checks.
sleep 1
printf '\nCleanup exact benchmark key:\n'
curl -fsS "${BASE_URL}/bench/prod-cache/cleanup/${STORE}/${SIZE}" | jq .
sleep 0.2
curl -fsS "${BASE_URL}/bench/prod-cache/cleanup/${STORE}/${SIZE}" >/dev/null
