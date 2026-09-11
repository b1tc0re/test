#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://app:8080}"
TOKEN="verify-$(date +%s)-$$"
REQUESTS="${VERIFY_REQUESTS:-40}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

printf 'Seeding token: %s\n' "$TOKEN"
curl -fsS "${BASE_URL}/bench/seed?token=${TOKEN}" | jq .

printf '\nSampling %s requests across RoadRunner workers...\n' "$REQUESTS"
for _ in $(seq 1 "$REQUESTS"); do
    curl -fsS "${BASE_URL}/bench/probe" >> "$TMP"
    printf '\n' >> "$TMP"
done

printf '\nUnique worker observations:\n'
jq -r '[.pid, .worker_id, (.worker_token // "-"), (.rr_memory_token // "-"), (.rr_redis_token // "-"), (.predis_token // "-")] | @tsv' "$TMP" \
    | sort -u \
    | awk 'BEGIN {printf "%-8s %-14s %-24s %-24s %-24s %-24s\n", "PID", "WORKER_ID", "WORKER_LOCAL", "RR_MEMORY", "RR_REDIS", "PREDIS_REDIS"} {printf "%-8s %-14s %-24s %-24s %-24s %-24s\n", $1, $2, $3, $4, $5, $6}'

RR_MEMORY_BAD="$(jq --arg token "$TOKEN" '[select(.rr_memory_token != $token)] | length' "$TMP" | awk '{s+=$1} END {print s+0}')"
RR_REDIS_BAD="$(jq --arg token "$TOKEN" '[select(.rr_redis_token != $token)] | length' "$TMP" | awk '{s+=$1} END {print s+0}')"
PREDIS_BAD="$(jq --arg token "$TOKEN" '[select(.predis_token != $token)] | length' "$TMP" | awk '{s+=$1} END {print s+0}')"
UNIQUE_WORKERS="$(jq -r '.pid' "$TMP" | sort -u | wc -l | tr -d ' ')"
WORKER_MISSES="$(jq --arg token "$TOKEN" 'select(.worker_token != $token) | 1' "$TMP" | wc -l | tr -d ' ')"

printf '\nChecks:\n'
printf '  unique PHP workers observed: %s\n' "$UNIQUE_WORKERS"
printf '  RR memory mismatches:        %s\n' "$RR_MEMORY_BAD"
printf '  RR Redis mismatches:         %s\n' "$RR_REDIS_BAD"
printf '  Predis mismatches:           %s\n' "$PREDIS_BAD"
printf '  worker-local misses:         %s\n' "$WORKER_MISSES"

if [[ "$RR_MEMORY_BAD" != "0" || "$RR_REDIS_BAD" != "0" || "$PREDIS_BAD" != "0" ]]; then
    printf '\nFAILED: shared stores did not return the seeded token on every request.\n' >&2
    exit 1
fi

printf '\nOK: RR memory, RR Redis and Predis are shared across the sampled PHP workers.\n'
if (( UNIQUE_WORKERS > 1 && WORKER_MISSES > 0 )); then
    printf 'OK: worker-local state is isolated per PHP worker, as expected.\n'
fi
