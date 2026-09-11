<?php

namespace App\Cache;

use Spiral\RoadRunner\KeyValue\Exception\SerializationException;
use Spiral\RoadRunner\KeyValue\Serializer\SerializerInterface;

final class IdentitySerializer implements SerializerInterface
{
    public function serialize(mixed $value): string
    {
        if (! is_string($value)) {
            throw new SerializationException('RoadRunner tiered Laravel store expects an already serialized string.');
        }

        return $value;
    }

    public function unserialize(string $value): mixed
    {
        return $value;
    }
}
