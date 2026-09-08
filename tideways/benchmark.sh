#!/usr/bin/env bash
set -Eeuo pipefail

ROUNDS="${ROUNDS:-1}"
DURATION="${DURATION:-10s}"
WARMUP="${WARMUP:-3s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
WARMUP_THREADS="${WARMUP_THREADS:-2}"
WARMUP_CONNECTIONS="${WARMUP_CONNECTIONS:-50}"
COOLDOWN="${COOLDOWN:-2}"

if [[ -n "${VARIANTS:-}" ]]; then
  read -r -a variants <<<"$VARIANTS"
else
  variants=(pure tideways-loaded tideways-monitor tideways-trace)
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
result_dir="results/${stamp}"
mkdir -p "$result_dir"

compose() {
  docker compose -f compose.yml "$@"
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

  compose logs "$service" >&2 || true
  return 1
}

validate_state() {
  local service="$1"
  local state
  state="$(compose exec -T "$service" curl -fsS http://127.0.0.1:8000/_benchmark/state)"
  echo "state (${service}): ${state}"

  grep -q '"laravel_octane":"1"' <<<"$state"
  grep -q '"php_sapi":"frankenphp"' <<<"$state"

  case "$service" in
    pure)
      grep -q '"tideways_extension":false' <<<"$state"
      grep -q '"bench_enabled":false' <<<"$state"
      ;;
    tideways-loaded)
      grep -q '"tideways_extension":true' <<<"$state"
      grep -q '"tideways_profiler_class":true' <<<"$state"
      grep -q '"bench_enabled":false' <<<"$state"
      ;;
    tideways-monitor)
      grep -q '"tideways_extension":true' <<<"$state"
      grep -q '"bench_enabled":true' <<<"$state"
      grep -q '"sample_rate":0' <<<"$state"
      ;;
    tideways-trace)
      grep -q '"tideways_extension":true' <<<"$state"
      grep -q '"bench_enabled":true' <<<"$state"
      grep -q '"sample_rate":100' <<<"$state"
      ;;
  esac
}

run_wrk() {
  local service="$1"
  local duration="$2"
  local threads="$3"
  local connections="$4"

  compose --profile benchmark run --rm --no-deps wrk \
    -t"$threads" -c"$connections" -d"$duration" --latency \
    "http://${service}:8000/up"
}

run_variant() {
  local round="$1"
  local service="$2"
  local out="${result_dir}/round-${round}-${service}.txt"

  echo
  echo "=== round ${round}: ${service} ==="
  compose stop "${variants[@]}" >/dev/null 2>&1 || true

  if [[ "$service" == tideways-monitor || "$service" == tideways-trace ]]; then
    compose up -d tideways-daemon
  fi

  compose up -d --force-recreate "$service"
  wait_ready "$service"
  validate_state "$service"

  echo "Warmup: ${WARMUP}"
  run_wrk "$service" "$WARMUP" "$WARMUP_THREADS" "$WARMUP_CONNECTIONS" >/dev/null

  echo "Benchmark: ${DURATION}, threads=${THREADS}, connections=${CONNECTIONS}"
  run_wrk "$service" "$DURATION" "$THREADS" "$CONNECTIONS" 2>&1 | tee "$out"

  local rps avg p99
  rps="$(awk '/Requests\/sec:/ {print $2}' "$out" | tail -n1)"
  avg="$(awk '$1 == "Latency" {print $2; exit}' "$out")"
  p99="$(awk '$1 == "99%" {print $2; exit}' "$out")"

  printf '%s,%s,%s,%s,%s\n' "$round" "$service" "$rps" "$avg" "$p99" >> "${result_dir}/results.csv"
  compose stop "$service" >/dev/null
  sleep "$COOLDOWN"
}

echo "Building Tideways benchmark images..."
compose build --pull "${variants[@]}"
compose pull tideways-daemon

printf 'round,variant,rps,avg_latency,p99_latency\n' > "${result_dir}/results.csv"

for round in $(seq 1 "$ROUNDS"); do
  for service in "${variants[@]}"; do
    run_variant "$round" "$service"
  done
done

baseline="${variants[0]}"
baseline_avg="$(awk -F, -v service="$baseline" 'NR > 1 && $2 == service {sum += $3; n++} END {printf "%.2f", sum/n}' "${result_dir}/results.csv")"

{
  echo
  echo "=== summary ==="
  printf '%-20s %12s %16s\n' "variant" "avg RPS" "vs ${baseline}"
  printf '%-20s %12s %16s\n' "--------------------" "------------" "----------------"

  for service in "${variants[@]}"; do
    avg="$(awk -F, -v service="$service" 'NR > 1 && $2 == service {sum += $3; n++} END {printf "%.2f", sum/n}' "${result_dir}/results.csv")"
    delta="$(awk -v base="$baseline_avg" -v avg="$avg" 'BEGIN {printf "%+.2f%%", ((avg/base)-1)*100}')"
    printf '%-20s %12s %16s\n' "$service" "$avg" "$delta"
  done

  echo "raw results: ${result_dir}"
} | tee "${result_dir}/summary.txt"
