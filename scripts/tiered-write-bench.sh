#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://app:8080}"
METRICS_URL="${METRICS_URL:-http://app:2112/metrics}"
THREADS="${THREADS:-10}"
CONNECTIONS="${CONNECTIONS:-100}"
DURATION="${DURATION:-20s}"
SIZE="${SIZE:-1024}"
SLOTS="${SLOTS:-256}"
WRITERS="${WRITERS:-?}"

metric() {
    local name="$1"
    curl -fsS "$METRICS_URL" | awk -v n="$name" '$1 == n {print $2; found=1; exit} END {if (!found) print 0}'
}

wait_for() {
    local url="$1"
    for _ in $(seq 1 60); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "Not ready: $url" >&2
    exit 1
}

wait_for "${BASE_URL}/bench/plain"
wait_for "$METRICS_URL"

# Delete only the fixed, namespaced writebench key range.
curl -fsS "${BASE_URL}/bench/tiered/writebench-cleanup/${SIZE}/${SLOTS}" >/dev/null

# Wait for any startup/proof writes to drain before taking the baseline.
for _ in $(seq 1 60); do
    [[ "$(metric rr_tiered_write_queue_depth)" == "0" ]] && break
    sleep 1
done

before_queued="$(metric rr_tiered_writes_queued_total)"
before_completed="$(metric rr_tiered_writes_completed_total)"
before_failed="$(metric rr_tiered_writes_failed_total)"
before_backpressure="$(metric rr_tiered_write_backpressure_total)"
before_dropped="$(metric rr_tiered_writes_dropped_total)"

output="$(wrk -t"${THREADS}" -c"${CONNECTIONS}" -d"${DURATION}" --latency "${BASE_URL}/bench/tiered/writebench/${SIZE}/${SLOTS}")"
rps="$(awk '/Requests\/sec:/ {print $2; exit}' <<<"$output")"
avg="$(awk '$1 == "Latency" {print $2; exit}' <<<"$output")"
p99="$(awk '$1 == "99%" {print $2; exit}' <<<"$output")"

after_queued="$(metric rr_tiered_writes_queued_total)"
after_completed="$(metric rr_tiered_writes_completed_total)"
after_failed="$(metric rr_tiered_writes_failed_total)"
after_backpressure="$(metric rr_tiered_write_backpressure_total)"
after_dropped="$(metric rr_tiered_writes_dropped_total)"
depth_after="$(metric rr_tiered_write_queue_depth)"
peak="$(metric rr_tiered_write_queue_peak)"
capacity="$(metric rr_tiered_write_queue_capacity)"

# Let Redis workers drain so we can verify that accepted writes actually complete.
for _ in $(seq 1 120); do
    [[ "$(metric rr_tiered_write_queue_depth)" == "0" ]] && break
    sleep 1
done

final_completed="$(metric rr_tiered_writes_completed_total)"
final_failed="$(metric rr_tiered_writes_failed_total)"
final_depth="$(metric rr_tiered_write_queue_depth)"

sub() { awk -v a="$1" -v b="$2" 'BEGIN {printf "%.0f", a-b}'; }

printf 'Tiered async write benchmark\n'
printf 'writers=%s threads=%s connections=%s duration=%s size=%sB slots=%s\n\n' "$WRITERS" "$THREADS" "$CONNECTIONS" "$DURATION" "$SIZE" "$SLOTS"
printf '%-20s %s\n' 'Requests/sec:' "${rps:-?}"
printf '%-20s %s\n' 'Avg latency:' "${avg:-?}"
printf '%-20s %s\n' 'P99 latency:' "${p99:-?}"
printf '%-20s %s\n' 'Queued delta:' "$(sub "$after_queued" "$before_queued")"
printf '%-20s %s\n' 'Completed @ end:' "$(sub "$after_completed" "$before_completed")"
printf '%-20s %s\n' 'Completed drained:' "$(sub "$final_completed" "$before_completed")"
printf '%-20s %s\n' 'Failed delta:' "$(sub "$final_failed" "$before_failed")"
printf '%-20s %s\n' 'Backpressure:' "$(sub "$after_backpressure" "$before_backpressure")"
printf '%-20s %s\n' 'Dropped:' "$(sub "$after_dropped" "$before_dropped")"
printf '%-20s %s / %s\n' 'Queue after wrk:' "$depth_after" "$capacity"
printf '%-20s %s\n' 'Queue peak:' "$peak"
printf '%-20s %s\n' 'Queue after drain:' "$final_depth"

curl -fsS "${BASE_URL}/bench/tiered/writebench-cleanup/${SIZE}/${SLOTS}" | jq .
