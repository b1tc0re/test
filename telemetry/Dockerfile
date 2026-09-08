FROM dunglas/frankenphp:1.12.7-php8.4-trixie AS base

ARG LARAVEL_SKELETON_VERSION=13.10.1
ARG LARAVEL_FRAMEWORK_VERSION=13.30.1
ARG LARAVEL_OCTANE_VERSION=2.19.1
ARG LARAVEL_OTEL_VERSION=2.2.4

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY benchmark-route.php /tmp/benchmark-route.php

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip curl \
    && rm -rf /var/lib/apt/lists/* \
    && install-php-extensions pcntl

WORKDIR /app

RUN composer create-project --no-interaction --prefer-dist \
        "laravel/laravel:${LARAVEL_SKELETON_VERSION}" /tmp/laravel \
    && cp -a /tmp/laravel/. /app/ \
    && rm -rf /tmp/laravel \
    && composer require --no-interaction --prefer-dist --with-all-dependencies \
        "laravel/framework:${LARAVEL_FRAMEWORK_VERSION}" \
        "laravel/octane:${LARAVEL_OCTANE_VERSION}" \
    && composer install --no-dev --no-interaction --prefer-dist --classmap-authoritative \
    && php artisan key:generate --force \
    && cp /tmp/benchmark-route.php routes/benchmark.php \
    && printf "\nrequire __DIR__.'/benchmark.php';\n" >> routes/web.php

RUN cp -a /app /app-pure \
    && composer require --no-interaction --prefer-dist --with-all-dependencies \
        "keepsuit/laravel-opentelemetry:${LARAVEL_OTEL_VERSION}" \
    && composer install --no-dev --no-interaction --prefer-dist --classmap-authoritative

EXPOSE 8000

CMD ["php", "artisan", "octane:frankenphp", "--host=0.0.0.0", "--port=8000", "--workers=2", "--max-requests=1000000"]

FROM base AS protobuf-ext
RUN install-php-extensions protobuf
