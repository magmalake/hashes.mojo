"""MurmurHash3_x86_32, plus the Iceberg Appendix-B pre-hash wrappers.

Iceberg's `bucket[N]` partition transform is `(hash(v) & Int32.MAX) % N`
where `hash` is MurmurHash3 x86-32 with seed 0 over a type-specific byte
serialization (spec: https://iceberg.apache.org/spec/#appendix-b-32-bit-hash-requirements).
"""

comptime _C1: UInt32 = 0xCC9E2D51
comptime _C2: UInt32 = 0x1B873593


def _rotl32(x: UInt32, r: Int) -> UInt32:
    return (x << UInt32(r)) | (x >> UInt32(32 - r))


def _fmix32(h_in: UInt32) -> UInt32:
    var h = h_in
    h ^= h >> 16
    h *= 0x85EBCA6B
    h ^= h >> 13
    h *= 0xC2B2AE35
    h ^= h >> 16
    return h


def murmur3_x86_32(data: Span[UInt8, _], seed: UInt32 = 0) -> UInt32:
    var n = len(data)
    var nblocks = n // 4
    var h1 = seed

    for block in range(nblocks):
        var i = block * 4
        var k1 = (
            UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
        )
        k1 *= _C1
        k1 = _rotl32(k1, 15)
        k1 *= _C2
        h1 ^= k1
        h1 = _rotl32(h1, 13)
        h1 = h1 * 5 + 0xE6546B64

    var tail_start = nblocks * 4
    var rem = n - tail_start
    var k1: UInt32 = 0
    if rem == 3:
        k1 ^= UInt32(data[tail_start + 2]) << 16
        k1 ^= UInt32(data[tail_start + 1]) << 8
        k1 ^= UInt32(data[tail_start])
        k1 *= _C1
        k1 = _rotl32(k1, 15)
        k1 *= _C2
        h1 ^= k1
    elif rem == 2:
        k1 ^= UInt32(data[tail_start + 1]) << 8
        k1 ^= UInt32(data[tail_start])
        k1 *= _C1
        k1 = _rotl32(k1, 15)
        k1 *= _C2
        h1 ^= k1
    elif rem == 1:
        k1 ^= UInt32(data[tail_start])
        k1 *= _C1
        k1 = _rotl32(k1, 15)
        k1 *= _C2
        h1 ^= k1

    h1 ^= UInt32(n)
    h1 = _fmix32(h1)
    return h1


def _to_int32(h: UInt32) -> Int32:
    return h.cast[DType.int32]()


def _le_bytes_i64(v: Int64) -> List[UInt8]:
    var u = v.cast[DType.uint64]()
    var out = List[UInt8]()
    for i in range(8):
        out.append(UInt8((u >> UInt64(8 * i)) & 0xFF))
    return out^


def _minimal_twos_complement_be(value: Int64) -> List[UInt8]:
    """Smallest big-endian two's-complement encoding of `value` (>= 1 byte),
    matching Java's `BigInteger.toByteArray()` used by Iceberg's decimal
    pre-hash."""
    var n = 1
    if value >= 0:
        while value >= (Int64(1) << Int64(8 * n - 1)):
            n += 1
    else:
        while value < -(Int64(1) << Int64(8 * n - 1)):
            n += 1
    var u = value.cast[DType.uint64]()
    var out = List[UInt8]()
    for i in range(n):
        var shift = 8 * (n - 1 - i)
        out.append(UInt8((u >> UInt64(shift)) & 0xFF))
    return out^


def iceberg_hash_long(v: Int64) -> Int32:
    var buf = _le_bytes_i64(v)
    return _to_int32(murmur3_x86_32(Span(buf), 0))


def iceberg_hash_int(v: Int32) -> Int32:
    return iceberg_hash_long(Int64(v))


def iceberg_hash_string(s: StringSlice) -> Int32:
    return _to_int32(murmur3_x86_32(s.as_bytes(), 0))


def iceberg_hash_bytes(data: Span[UInt8, _]) -> Int32:
    return _to_int32(murmur3_x86_32(data, 0))


def iceberg_hash_uuid(hi: UInt64, lo: UInt64) -> Int32:
    var out = List[UInt8]()
    for i in range(8):
        out.append(UInt8((hi >> UInt64(8 * (7 - i))) & 0xFF))
    for i in range(8):
        out.append(UInt8((lo >> UInt64(8 * (7 - i))) & 0xFF))
    return _to_int32(murmur3_x86_32(Span(out), 0))


def iceberg_hash_decimal(unscaled: Int64) -> Int32:
    var buf = _minimal_twos_complement_be(unscaled)
    return _to_int32(murmur3_x86_32(Span(buf), 0))


def iceberg_bucket(hash: UInt32, n: Int) -> Int:
    return Int(hash & 0x7FFFFFFF) % n
