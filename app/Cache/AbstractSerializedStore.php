<?php

namespace App\Cache;

use Illuminate\Cache\RetrievesMultipleKeys;
use Illuminate\Contracts\Cache\Store;
use LogicException;

abstract class AbstractSerializedStore implements Store
{
    use RetrievesMultipleKeys;

    public function __construct(
        protected string $prefix = '',
        protected array|bool|null $serializableClasses = null,
    ) {
    }

    public function get($key)
    {
        $value = $this->rawGet($this->prefix.$key);

        return $value !== null ? $this->unserializeValue($value) : null;
    }

    public function put($key, $value, $seconds)
    {
        return $this->rawPut(
            $this->prefix.$key,
            $this->serializeValue($value),
            (int) max(1, $seconds),
        );
    }

    public function increment($key, $value = 1)
    {
        throw new LogicException('Atomic increment is not implemented by the tiered benchmark store yet.');
    }

    public function decrement($key, $value = 1)
    {
        throw new LogicException('Atomic decrement is not implemented by the tiered benchmark store yet.');
    }

    public function forever($key, $value)
    {
        return $this->rawPut(
            $this->prefix.$key,
            $this->serializeValue($value),
            0,
        );
    }

    public function touch($key, $seconds)
    {
        return $this->rawTouch($this->prefix.$key, (int) max(1, $seconds));
    }

    public function forget($key)
    {
        return $this->rawForget($this->prefix.$key);
    }

    public function flush()
    {
        // Deliberately unsupported for the benchmark drivers. Never map a
        // Laravel cache flush to FLUSHDB on a Redis DB shared with production.
        return false;
    }

    public function getPrefix()
    {
        return $this->prefix;
    }

    protected function serializeValue(mixed $value): string
    {
        // Mirror Illuminate\Cache\RedisStore semantics. Arrays/DTO-toArray()
        // take the PHP serialize() path in all three compared drivers.
        if (is_numeric($value) && is_finite($value)) {
            return (string) $value;
        }

        return serialize($value);
    }

    protected function unserializeValue(string $value): mixed
    {
        if (is_numeric($value)) {
            return $value;
        }

        if ($this->serializableClasses !== null) {
            return unserialize($value, ['allowed_classes' => $this->serializableClasses]);
        }

        return unserialize($value);
    }

    abstract protected function rawGet(string $key): ?string;

    abstract protected function rawPut(string $key, string $value, int $seconds): bool;

    abstract protected function rawForget(string $key): bool;

    abstract protected function rawTouch(string $key, int $seconds): bool;
}
