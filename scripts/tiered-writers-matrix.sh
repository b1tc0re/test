#!/usr/bin/env bash
set -euo pipefail

WRITERS_LIST="${WRITERS_LIST:-4 8 16}"
DURATION="${DURATION:-20s}"
THREADS="${THREADS:-10}"
CONNECTIONS="${CONNECTIONS:-100}"
SIZE="${SIZE:-1024}"
SLOTS="${SLOTS:-256}"

for writers in $WRITERS_LIST; do
    printf '\n============================================================\n'
    printf 'Tiered writer shards: %s\n' "$writers"
    printf '============================================================\n'

    TIERED_WRITERS="$writers" docker compose up -d --force-recreate app

    for _ in $(seq 1 60); do
        if docker compose exec -T app curl -fsS http://127.0.0.1:8080/bench/plain >/dev/null 2>&1 \
            && docker compose exec -T app curl -fsS http://127.0.0.1:2112/metrics >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    docker compose run --rm \
        -e WRITERS="$writers" \
        -e DURATION="$DURATION" \
        -e THREADS="$THREADS" \
        -e CONNECTIONS="$CONNECTIONS" \
        -e SIZE="$SIZE" \
        -e SLOTS="$SLOTS" \
        bench bash /scripts/tiered-write-bench.sh http://app:8080
done
