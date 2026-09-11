<?php

namespace App\Cache;

use RuntimeException;

final class FrankenTieredStore extends AbstractSerializedStore
{
    public function __construct(
        string $prefix = '',
        array|bool|null $serializableClasses = null,
    ) {
        if (! function_exists('franken_tiered_get')) {
            throw new RuntimeException('FrankenPHP native tiered extension is not loaded.');
        }

        parent::__construct($prefix, $serializableClasses);
    }

    protected function rawGet(string $key): ?string
    {
        $value = franken_tiered_get($key);

        if ($value === false) {
            throw new RuntimeException('FrankenPHP native tiered cache read failed.');
        }

        return $value;
    }

    protected function rawPut(string $key, string $value, int $seconds): bool
    {
        return franken_tiered_put($key, $value, $seconds);
    }

    protected function rawForget(string $key): bool
    {
        return franken_tiered_forget($key);
    }

    protected function rawTouch(string $key, int $seconds): bool
    {
        return franken_tiered_touch($key, $seconds);
    }
}
