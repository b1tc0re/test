<?php

namespace App\Cache;

use Spiral\RoadRunner\KeyValue\StorageInterface;

final class RoadRunnerTieredStore extends AbstractSerializedStore
{
    public function __construct(
        private readonly StorageInterface $storage,
        string $prefix = '',
        array|bool|null $serializableClasses = null,
    ) {
        parent::__construct($prefix, $serializableClasses);
    }

    protected function rawGet(string $key): ?string
    {
        $value = $this->storage->get($key);

        return $value === null ? null : (string) $value;
    }

    protected function rawPut(string $key, string $value, int $seconds): bool
    {
        return $this->storage->set($key, $value, $seconds > 0 ? $seconds : null);
    }

    protected function rawForget(string $key): bool
    {
        return $this->storage->delete($key);
    }

    protected function rawTouch(string $key, int $seconds): bool
    {
        $value = $this->storage->get($key);
        if ($value === null) {
            return false;
        }

        return $this->storage->set($key, (string) $value, $seconds);
    }
}
