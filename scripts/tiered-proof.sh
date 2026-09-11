#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://app:8080}"
TOKEN="tiered-proof-$(date +%s)-$$"

cleanup() {
    curl -fsS "${BASE_URL}/bench/cleanup" >/dev/null || true
}
trap cleanup EXIT

printf 'Tiered cache proof\n'
printf 'token=%s\n\n' "$TOKEN"

cleanup

printf '1. SET through tiered store (L1 sync, Redis async):\n'
SET_JSON="$(curl -fsS "${BASE_URL}/bench/tiered/proof/set?token=${TOKEN}")"
printf '%s\n' "$SET_JSON" | jq .

# Give the Go writer a small observation window. This is not needed for L1;
# it only makes the L2 verification deterministic on a real network.
sleep 0.05

printf '\n2. Clear only tiered L1 (driver Clear intentionally never FLUSHDBs Redis):\n'
curl -fsS "${BASE_URL}/bench/tiered/proof/clear-l1" | jq .

printf '\n3. GET after L1 clear; value must be restored from Redis L2:\n'
GET_JSON="$(curl -fsS "${BASE_URL}/bench/tiered/proof/get")"
printf '%s\n' "$GET_JSON" | jq .

VALUE="$(printf '%s\n' "$GET_JSON" | jq -r '.value // ""')"
if [[ "$VALUE" != "$TOKEN" ]]; then
    printf '\nFAILED: expected %s, got %s\n' "$TOKEN" "$VALUE" >&2
    exit 1
fi

printf '\nOK: tiered SET populated L1 and Redis L2; after L1 clear the value was recovered from Redis.\n'
