<?php

namespace App\Support;

final class ProdLikePayload
{
    /** @var array<int, array<string, mixed>> */
    private static array $payloads = [];

    /** @return array<string, mixed> */
    public static function make(int $targetSerializedBytes): array
    {
        if (isset(self::$payloads[$targetSerializedBytes])) {
            return self::$payloads[$targetSerializedBytes];
        }

        $payload = [
            'id' => 160,
            'slug' => 'benchmark-gift',
            'name' => 'Подарок для production-like cache benchmark',
            'active' => true,
            'score' => 98.75,
            'filters' => [
                ['field_id' => 1, 'value_id' => 10, 'name' => 'Новый год'],
                ['field_id' => 2, 'value_id' => 21, 'name' => 'Жене'],
                ['field_id' => 5, 'value_id' => 7, 'name' => 'Путешествия'],
                ['field_id' => 7, 'value_id' => 3, 'name' => 'Женский'],
            ],
            'images' => [
                [
                    'id' => 1,
                    'src' => '/images/benchmark/1.webp',
                    'width' => 320,
                    'height' => 175,
                ],
                [
                    'id' => 2,
                    'src' => '/images/benchmark/2.webp',
                    'width' => 640,
                    'height' => 350,
                ],
            ],
            'meta' => [
                'manual_score' => 50,
                'views' => 12345,
                'choice' => 321,
                'price_from' => 2500,
                'price_to' => 5000,
            ],
            'padding' => '',
        ];

        // Bring PHP serialize() output close to the requested size. The exact
        // serialized byte count is reported by the benchmark before each run.
        for ($i = 0; $i < 4; $i++) {
            $current = strlen(serialize($payload));
            $delta = $targetSerializedBytes - $current;

            if (abs($delta) <= 2 || ($delta < 0 && $payload['padding'] === '')) {
                break;
            }

            if ($delta > 0) {
                $payload['padding'] .= str_repeat('x', $delta);
            } else {
                $payload['padding'] = substr($payload['padding'], 0, max(0, strlen($payload['padding']) + $delta));
            }
        }

        return self::$payloads[$targetSerializedBytes] = $payload;
    }

    public static function serializedBytes(int $targetSerializedBytes): int
    {
        return strlen(serialize(self::make($targetSerializedBytes)));
    }
}
