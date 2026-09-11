FROM ghcr.io/roadrunner-server/roadrunner:2025.1.15 AS roadrunner
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
COPY --from=roadrunner /usr/bin/rr /usr/local/bin/rr

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
COPY routes/web.php /app/routes/web.php
COPY .rr.yaml /app/.rr.yaml
COPY php.ini /usr/local/etc/php/conf.d/99-benchmark.ini
COPY entrypoint.sh /usr/local/bin/benchmark-entrypoint

RUN chmod +x /usr/local/bin/benchmark-entrypoint \
    && mkdir -p /app/storage/framework/cache /app/storage/framework/sessions /app/storage/framework/views /app/storage/logs /app/bootstrap/cache

EXPOSE 8080

ENTRYPOINT ["benchmark-entrypoint"]
