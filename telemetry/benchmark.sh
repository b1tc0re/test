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

variants=(pure otel-disabled otel-sdk otel-http otel-http-otlp-php otel-http-otlp-ext)
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

  case "$service" in
    pure)
      grep -q '"package_installed":false' <<<"$state"
      ;;
    otel-disabled)
      grep -q '"package_installed":true' <<<"$state"
      grep -q '"provider_loaded":true' <<<"$state"
      grep -q '"sdk_disabled":true' <<<"$state"
      ;;
    otel-sdk)
      grep -q '"sdk_disabled":false' <<<"$state"
      grep -q '"http_server_enabled":false' <<<"$state"
      grep -q '"traces_exporter":"null"' <<<"$state"
      ;;
    otel-http)
      grep -q '"sdk_disabled":false' <<<"$state"
      grep -q '"http_server_enabled":true' <<<"$state"
      grep -q '"traces_exporter":"null"' <<<"$state"
      ;;
    otel-http-otlp-php)
      grep -q '"sdk_disabled":false' <<<"$state"
      grep -q '"http_server_enabled":true' <<<"$state"
      grep -q '"traces_exporter":"otlp"' <<<"$state"
      grep -q '"protobuf_extension":false' <<<"$state"
      ;;
    otel-http-otlp-ext)
      grep -q '"sdk_disabled":false' <<<"$state"
      grep -q '"http_server_enabled":true' <<<"$state"
      grep -q '"traces_exporter":"otlp"' <<<"$state"
      grep -q '"protobuf_extension":true' <<<"$state"
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

  if [[ "$service" == otel-http-otlp-* ]]; then
    compose up -d collector
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

average_rps() {
  local service="$1"
  awk -F, -v service="$service" '
    NR > 1 && $2 == service {sum += $3; n++}
    END {if (!n) exit 1; printf "%.2f", sum/n}
  ' "${result_dir}/results.csv"
}

rotate_order() {
  local round="$1"
  local offset=$(( (round - 1) % ${#variants[@]} ))
  local ordered=()

  for i in $(seq 0 $((${#variants[@]} - 1))); do
    ordered+=("${variants[$(( (i + offset) % ${#variants[@]} ))]}")
  done

  printf '%s\n' "${ordered[@]}"
}

echo "Building telemetry benchmark images..."
compose build --pull "${variants[@]}"
compose pull collector

printf 'round,variant,rps,avg_latency,p99_latency\n' > "${result_dir}/results.csv"

for round in $(seq 1 "$ROUNDS"); do
  mapfile -t order < <(rotate_order "$round")
  for service in "${order[@]}"; do
    run_variant "$round" "$service"
  done
done

pure_avg="$(average_rps pure)"
http_avg="$(average_rps otel-http)"

{
  echo
  echo "=== summary ==="
  printf '%-22s %12s %14s %16s\n' "variant" "avg RPS" "vs pure" "vs http-null"
  printf '%-22s %12s %14s %16s\n' "----------------------" "------------" "--------------" "----------------"

  for service in "${variants[@]}"; do
    avg="$(average_rps "$service")"
    delta_pure="$(awk -v pure="$pure_avg" -v avg="$avg" 'BEGIN {printf "%+.2f%%", ((avg/pure)-1)*100}')"
    delta_http="-"
    if [[ "$service" == otel-http* ]]; then
      delta_http="$(awk -v http="$http_avg" -v avg="$avg" 'BEGIN {printf "%+.2f%%", ((avg/http)-1)*100}')"
    fi
    printf '%-22s %12s %14s %16s\n' "$service" "$avg" "$delta_pure" "$delta_http"
  done

  echo "raw results: ${result_dir}"
} | tee "${result_dir}/summary.txt"
