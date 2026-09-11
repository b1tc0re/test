# Laravel 13 + RoadRunner KV benchmark

Небольшой стенд для проверки двух вещей:

1. действительно ли RoadRunner KV `memory` виден всем Laravel/Octane PHP workers;
2. сколько он стоит по latency/RPS относительно локальной памяти worker-а и Redis.

Стенд специально минимальный: Laravel 13, Laravel Octane, RoadRunner `v2025.1.15`, официальный `spiral/roadrunner-kv` и Redis без persistence.

## Что сравнивается

| Backend | Где живут данные | Между PHP workers | После рестарта RoadRunner |
|---|---|---:|---:|
| `worker` | static memory PHP process | нет | нет |
| `rr` | RoadRunner KV `memory` plugin | да | нет |
| `redis` | отдельный Redis process | да | да, пока жив Redis |

`worker` — практически нижняя граница стоимости доступа. Он нужен не как реальный общий cache, а как reference point.

RoadRunner KV вызывается через официальный PHP client (`spiral/roadrunner-kv`) по RPC. RPC client создаётся один раз на PHP worker и затем переиспользуется. Redis client устроен так же — один соединённый client на worker.

## Запуск

```bash
git clone -b bench/roadrunner-kv --single-branch https://github.com/b1tc0re/test.git roadrunner-benchmark
cd roadrunner-benchmark
make up
make verify
make bench
```

Посмотреть версии:

```bash
make versions
```

Остановить стенд:

```bash
make down
```

## Сначала обязательно `make verify`

Проверка записывает один token одновременно в worker-local память, RR KV и Redis, после чего делает серию запросов к разным PHP workers.

При `RR_WORKERS=4` нормальная картина примерно такая:

```text
PID      WORKER_ID      WORKER_LOCAL             RR_KV                    REDIS
123      a1...          verify-...               verify-...               verify-...
124      b2...          -                        verify-...               verify-...
125      c3...          -                        verify-...               verify-...
126      d4...          -                        verify-...               verify-...
```

То есть локальное состояние есть только у worker-а, который получил `/bench/seed`, а RoadRunner KV и Redis возвращают token независимо от PID.

## Нагрузочный тест

Быстрый набор, payload 1 KiB:

```bash
make bench
```

По умолчанию это:

```text
threads=4
connections=100
duration=10s
sizes=1024
mode=all
```

Проверяются:

```text
/bench/plain
/bench/worker/read/1024
/bench/rr/read/1024
/bench/redis/read/1024
/bench/worker/write/1024
/bench/rr/write/1024
/bench/redis/write/1024
```

Вывод уже компактный — `REQ/SEC`, средняя latency и p99. Его можно целиком прислать обратно в ChatGPT.

Полный прогон по 64 B, 1 KiB, 16 KiB и 64 KiB:

```bash
make bench-full
```

Параметры можно менять без редактирования файлов:

```bash
make bench THREADS=8 CONNECTIONS=200 DURATION=20s SIZES="1024 16384" MODE=read
```

`MODE=read` исключает write-тесты. `MODE=all` тестирует и чтение, и запись.

## Масштабирование по числу workers

Очень важный тест именно для RoadRunner:

```bash
make matrix WORKERS_LIST="1 2 4 8 16" MODE=read DURATION=10s
```

Он последовательно пересоздаёт только контейнер приложения с разным `RR_WORKERS` и запускает одинаковую нагрузку.

Это позволяет увидеть, где находится sweet spot конкретно на твоём CPU. Если после определённого числа workers RPS перестаёт расти или latency начинает увеличиваться, дальнейшее увеличение pool уже не помогает.

## Что означают результаты

Самое интересное отношение:

```text
RR KV read RPS / plain RPS
Redis read RPS / plain RPS
RR KV read latency / worker read latency
RR KV read latency / Redis read latency
```

Если RR KV окажется заметно быстрее Redis при нескольких workers, он хорошо подходит для горячих эфемерных данных: предварительно рассчитанных DTO/lookup tables, небольших результатов фильтрации, feature/config snapshots и другого cache, который допустимо потерять при рестарте RoadRunner.

Если разница с Redis небольшая, Redis обычно удобнее эксплуатационно: данные не привязаны к одному RoadRunner process и доступны другим pod/process/CLI.

## Важное ограничение

Это benchmark **одного RoadRunner instance/container**. RR KV `memory` общий между PHP workers внутри этого RoadRunner, но это не distributed cache между несколькими RoadRunner pod-ами. Для Kubernetes с несколькими web pods Redis остаётся общей точкой, если данные должны быть одинаковыми во всех pods.

Также не сравнивай абсолютные цифры с чужими benchmark-ами. Для решения важнее прогнать RR KV и Redis на одном и том же железе, с одинаковым количеством workers/connections и смотреть относительную разницу.
