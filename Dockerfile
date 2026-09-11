FROM golang:1.26.4-bookworm AS rr-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch v2025.1.15 https://github.com/roadrunner-server/roadrunner.git /src/roadrunner
COPY rr-tiered /src/rr-tiered

WORKDIR /src/roadrunner
RUN go mod edit -require=github.com/b1tc0re/rr-tiered@v0.0.0 \
    && go mod edit -replace=github.com/b1tc0re/rr-tiered=/src/rr-tiered \
    && sed -i '/"github.com\/roadrunner-server\/redis\/v5"/a\	tiered "github.com/b1tc0re/rr-tiered"' container/plugins.go \
    && sed -i '/&redis.Plugin{},/a\		&tiered.Plugin{},' container/plugins.go \
    && go mod tidy \
    && CGO_ENABLED=0 go build -trimpath -o /out/rr ./cmd/rr

FROM composer:2 AS composer
FROM php:8.4-cli-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        unzip \
        libsqlite3-dev \
        $PHPIZE_DEPS \
    && docker-php-ext-install pcntl sockets opcache pdo_sqlite \
    && pecl install protobuf \
    && docker-php-ext-enable protobuf \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/local/bin/composer
COPY --from=rr-builder /out/rr /usr/local/bin/rr

WORKDIR /app

RUN composer create-project laravel/laravel:^13.0 /app --prefer-dist --no-interaction \
    && composer require \
        laravel/octane:^2.17 \
        spiral/roadrunner-http:^3.3 \
        spiral/roadrunner-kv:^4.0 \
        predis/predis:^3.0 \
        --no-interaction \
    && composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction

COPY app/Support/BenchmarkStores.php /app/app/Support/BenchmarkStores.php
COPY app/Cache /app/app/Cache
COPY app/Providers/AppServiceProvider.php /app/app/Providers/AppServiceProvider.php
COPY routes/web.php /app/routes/web.php
COPY .rr.yaml /app/.rr.yaml
COPY php.ini /usr/local/etc/php/conf.d/99-benchmark.ini
COPY entrypoint.sh /usr/local/bin/benchmark-entrypoint

RUN composer dump-autoload --no-dev --optimize --no-interaction \
    && chmod +x /usr/local/bin/benchmark-entrypoint \
    && mkdir -p /app/storage/framework/cache /app/storage/framework/sessions /app/storage/framework/views /app/storage/logs /app/bootstrap/cache

EXPOSE 8080

ENTRYPOINT ["benchmark-entrypoint"]