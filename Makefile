DURATION ?= 10s
THREADS ?= 4
CONNECTIONS ?= 100
SIZES ?= 1024
MODE ?= all
OPS_LIST ?= 1 10 100 1000
SIZE ?= 1024

.PHONY: up down logs verify tiered-proof bench bench-full microbench cleanup matrix versions

up:
	docker compose build app bench
	docker compose up -d app redis

down:
	docker compose down -v

logs:
	docker compose logs -f app

verify:
	docker compose run --rm bench bash /scripts/verify.sh http://app:8080

tiered-proof:
	docker compose run --rm bench bash /scripts/tiered-proof.sh http://app:8080

bench:
	docker compose run --rm \
		-e DURATION="$(DURATION)" \
		-e THREADS="$(THREADS)" \
		-e CONNECTIONS="$(CONNECTIONS)" \
		-e SIZES="$(SIZES)" \
		-e MODE="$(MODE)" \
		bench bash /scripts/bench.sh http://app:8080

bench-full:
	$(MAKE) bench SIZES="64 1024 16384 65536"

microbench:
	docker compose run --rm \
		-e DURATION="$(DURATION)" \
		-e THREADS="$(THREADS)" \
		-e CONNECTIONS="$(CONNECTIONS)" \
		-e OPS_LIST="$(OPS_LIST)" \
		-e SIZE="$(SIZE)" \
		bench bash /scripts/microbench.sh http://app:8080

cleanup:
	docker compose run --rm bench sh -lc 'curl -fsS http://app:8080/bench/cleanup | jq .'

matrix:
	WORKERS_LIST="$(WORKERS_LIST)" DURATION="$(DURATION)" THREADS="$(THREADS)" CONNECTIONS="$(CONNECTIONS)" SIZES="$(SIZES)" MODE="$(MODE)" bash ./scripts/matrix.sh

versions:
	docker compose exec -T app sh -lc 'php -v | head -n1; rr --version; php artisan --version; composer show laravel/octane spiral/roadrunner-http spiral/roadrunner-kv predis/predis 2>/dev/null || true'
