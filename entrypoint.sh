#!/usr/bin/env sh
set -eu

exec rr serve -c /app/.rr.yaml \
  -o "http.pool.num_workers=${RR_WORKERS:-4}" \
  -o "http.pool.max_jobs=${RR_MAX_REQUESTS:-1000000}"
