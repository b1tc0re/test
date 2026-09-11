#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:?base URL required}"
LABEL="${2:?runtime label required}"
THREADS="${THREADS:-10}"
CONNECTIONS="${CONNECTIONS:-100}"
DURATION="${DURATION:-30s}"
SIZE="${SIZE:-1024}"
OPS_LIST="${OPS_LIST:-1 5 10}"
PROBE_REQUESTS="${PROBE_REQUESTS:-40}"

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

    printf '%-32s %14s %14s %14s\n' "$label" "${rps:-?}" "${avg:-?}" "${p99:-?}"
}

wait_for_runtime

# Give all workers some traffic before sampling their identity.
wrk -t2 -c20 -d2s "${BASE_URL}/bench/plain" >/dev/null

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
for _ in $(seq 1 "$PROBE_REQUESTS"); do
    curl -fsS "${BASE_URL}/bench/runtime/probe" >> "$TMP"
    printf '\n' >> "$TMP"
done

printf '\n%s\n' "$LABEL"
printf 'threads=%s connections=%s duration=%s size=%sB cache_ops="%s"\n' \
    "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZE" "$OPS_LIST"
printf 'Execution observations (PID / worker-local id / backend / SAPI / ZTS / server):\n'
jq -r '[.pid, .worker_id, .cache_backend, .sapi, .zts, (.server_software // "-")] | @tsv' "$TMP" | sort -u

curl -fsS "${BASE_URL}/bench/runtime/cache/seed/${SIZE}" >/dev/null

printf '\n%-32s %14s %14s %14s\n' 'ENDPOINT' 'REQ/SEC' 'AVG LAT' 'P99 LAT'
printf '%-32s %14s %14s %14s\n' '--------------------------------' '--------------' '--------------' '--------------'
run_wrk 'plain Laravel' '/bench/plain'

for ops in $OPS_LIST; do
    run_wrk "cache read ${ops}/request" "/bench/runtime/cache/read/${ops}/${SIZE}"
done
