#!/usr/bin/env bash
set -Eeuo pipefail

ROUNDS="${ROUNDS:-5}"
DURATION="${DURATION:-30s}"
WARMUP="${WARMUP:-10s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
WARMUP_THREADS="${WARMUP_THREADS:-2}"
WARMUP_CONNECTIONS="${WARMUP_CONNECTIONS:-50}"
COOLDOWN="${COOLDOWN:-2}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
result_dir="results/${stamp}"
mkdir -p "$result_dir"

compose() {
  docker compose "$@"
}

cleanup() {
  compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_ready() {
  local service="$1"

  for _ in $(seq 1 90); do
    if compose exec -T "$service" curl -fsS http://127.0.0.1:8000/up >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Service ${service} did not become ready" >&2
  compose logs "$service" >&2 || true
  return 1
}

verify_worker_mode() {
  local service="$1"
  local state

  state="$(compose exec -T "$service" curl -fsS http://127.0.0.1:8000/__benchmark/state)"
  echo "worker-mode state (${service}): ${state}"

  php -r '
    $state = json_decode($argv[1], true, 512, JSON_THROW_ON_ERROR);

    $ok = in_array($state["laravel_octane"] ?? null, ["1", "true"], true)
        && ($state["sdk_disabled"] ?? true) === false
        && ($state["worker_manager_resolved"] ?? false) === true
        && ($state["request_terminated_listeners"] ?? 0) > 0;

    if (! $ok) {
        fwrite(STDERR, "Worker-mode verification failed: ".json_encode($state, JSON_UNESCAPED_SLASHES).PHP_EOL);
        exit(1);
    }
  ' "$state"
}

run_wrk() {
  local service="$1"
  local duration="$2"
  local threads="$3"
  local connections="$4"

  compose --profile benchmark run --rm --no-deps wrk \
    -t"$threads" \
    -c"$connections" \
    -d"$duration" \
    --latency \
    "http://${service}:8000/up"
}

run_variant() {
  local round="$1"
  local service="$2"
  local out="${result_dir}/round-${round}-${service}.txt"

  echo
  echo "=== round ${round}: ${service} ==="

  compose stop carbon time >/dev/null 2>&1 || true
  compose up -d --force-recreate "$service"
  wait_ready "$service"
  verify_worker_mode "$service"

  echo "Warmup: ${WARMUP}"
  run_wrk "$service" "$WARMUP" "$WARMUP_THREADS" "$WARMUP_CONNECTIONS" >/dev/null

  echo "Benchmark: ${DURATION}, threads=${THREADS}, connections=${CONNECTIONS}"
  run_wrk "$service" "$DURATION" "$THREADS" "$CONNECTIONS" 2>&1 | tee "$out"

  local rps avg p99
  rps="$(awk '/Requests\/sec:/ {print $2}' "$out" | tail -n1)"
  avg="$(awk '$1 == "Latency" {print $2; exit}' "$out")"
  p99="$(awk '$1 == "99%" {print $2; exit}' "$out")"

  if [[ -z "$rps" ]]; then
    echo "Failed to parse Requests/sec from ${out}" >&2
    return 1
  fi

  printf '%s,%s,%s,%s,%s\n' "$round" "$service" "$rps" "$avg" "$p99" >> "${result_dir}/results.csv"

  compose stop "$service" >/dev/null
  sleep "$COOLDOWN"
}

average_rps() {
  local service="$1"
  awk -F, -v service="$service" '
    NR > 1 && $2 == service { sum += $3; count++ }
    END {
      if (count == 0) exit 1
      printf "%.2f", sum / count
    }
  ' "${result_dir}/results.csv"
}

echo "Building benchmark images..."
compose build --pull carbon time

{
  echo "date_utc=${stamp}"
  echo "docker=$(docker --version)"
  echo "compose=$(docker compose version)"
  echo
  echo "[carbon php]"
  compose run --rm --no-deps carbon php -v
  echo
  echo "[carbon packages]"
  for package in laravel/framework laravel/octane keepsuit/laravel-opentelemetry; do
    compose run --rm --no-deps carbon composer show "$package" --no-ansi \
      | awk -F' *: *' '/^(name|versions) *:/ {print}'
  done
  echo
  echo "[carbon worker mode source]"
  compose run --rm --no-deps carbon sh -lc \
    "grep -nE 'Carbon::now\\(\\)->getTimestamp\\(\\)|time\\(\\)' vendor/keepsuit/laravel-opentelemetry/src/WorkerMode/WorkerModeManager.php"
  echo
  echo "[time worker mode source]"
  compose run --rm --no-deps time sh -lc \
    "grep -nE 'Carbon::now\\(\\)->getTimestamp\\(\\)|time\\(\\)' vendor/keepsuit/laravel-opentelemetry/src/WorkerMode/WorkerModeManager.php"
} | tee "${result_dir}/environment.txt"

printf 'round,variant,rps,avg_latency,p99_latency\n' > "${result_dir}/results.csv"

for round in $(seq 1 "$ROUNDS"); do
  if (( round % 2 == 1 )); then
    order=(carbon time)
  else
    order=(time carbon)
  fi

  for service in "${order[@]}"; do
    run_variant "$round" "$service"
  done
done

carbon_avg="$(average_rps carbon)"
time_avg="$(average_rps time)"
delta="$(awk -v carbon="$carbon_avg" -v time="$time_avg" 'BEGIN { printf "%.2f", ((time / carbon) - 1) * 100 }')"

{
  echo
  echo "=== summary ==="
  echo "carbon average RPS: ${carbon_avg}"
  echo "time average RPS:   ${time_avg}"
  echo "time vs carbon:     ${delta}%"
  echo "raw results:        ${result_dir}"
} | tee "${result_dir}/summary.txt"
