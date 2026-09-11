#!/usr/bin/env bash
set -euo pipefail

WORKERS_LIST="${WORKERS_LIST:-1 2 4 8}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
DURATION="${DURATION:-8s}"
SIZES="${SIZES:-1024}"
MODE="${MODE:-read}"

for workers in $WORKERS_LIST; do
    printf '\n============================================================\n'
    printf 'RoadRunner workers: %s\n' "$workers"
    printf '============================================================\n'

    RR_WORKERS="$workers" docker compose up -d --force-recreate app >/dev/null

    for _ in $(seq 1 60); do
        if docker compose exec -T app curl -fsS http://127.0.0.1:8080/bench/plain >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    docker compose run --rm \
        -e THREADS="$THREADS" \
        -e CONNECTIONS="$CONNECTIONS" \
        -e DURATION="$DURATION" \
        -e SIZES="$SIZES" \
        -e MODE="$MODE" \
        bench /scripts/bench.sh http://app:8080
done
