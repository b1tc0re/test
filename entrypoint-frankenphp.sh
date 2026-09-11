#!/usr/bin/env sh
set -eu

exec php artisan octane:frankenphp \
  --host=0.0.0.0 \
  --port=8080 \
  --admin-host=127.0.0.1 \
  --admin-port=2019 \
  --workers="${FRANKENPHP_WORKERS:-4}" \
  --max-requests="${FRANKENPHP_MAX_REQUESTS:-1000000}" \
  --log-level=ERROR
