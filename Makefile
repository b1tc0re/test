DURATION ?= 10s
THREADS ?= 4
CONNECTIONS ?= 100
SIZES ?= 1024
MODE ?= all

.PHONY: up down logs verify bench bench-full matrix versions

up:
	docker compose up -d --build app redis

down:
	docker compose down -v

logs:
	docker compose logs -f app

verify:
	docker compose run --rm bench /scripts/verify.sh http://app:8080

bench:
	docker compose run --rm \
		-e DURATION="$(DURATION)" \
		-e THREADS="$(THREADS)" \
		-e CONNECTIONS="$(CONNECTIONS)" \
		-e SIZES="$(SIZES)" \
		-e MODE="$(MODE)" \
		bench /scripts/bench.sh http://app:8080

bench-full:
	$(MAKE) bench SIZES="64 1024 16384 65536"

matrix:
	WORKERS_LIST="$(WORKERS_LIST)" DURATION="$(DURATION)" THREADS="$(THREADS)" CONNECTIONS="$(CONNECTIONS)" SIZES="$(SIZES)" MODE="$(MODE)" ./scripts/matrix.sh

versions:
	docker compose exec -T app sh -lc 'php -v | head -n1; rr --version; php artisan --version; composer show laravel/octane spiral/roadrunner-http spiral/roadrunner-kv predis/predis 2>/dev/null || true'
