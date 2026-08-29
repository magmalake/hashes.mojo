"""Unit tests for hashes.mojo: hand-computed vectors, the CRC-32/xxHash spec
vectors, the Iceberg Appendix-B test vectors, and Python cross-checks
(zlib.crc32 / mmh3.hash / xxhash.xxh64) baked in as constants."""

from std.testing import TestSuite, assert_equal

from hashes import (
    Crc32,
    Xxh64,
    crc32,
    iceberg_bucket,
    iceberg_hash_bytes,
    iceberg_hash_decimal,
    iceberg_hash_int,
    iceberg_hash_long,
    iceberg_hash_string,
    iceberg_hash_uuid,
    murmur3_x86_32,
    xxh64,
)


def _bytes_of(s: StringSlice) -> List[UInt8]:
    var out = List[UInt8]()
    for b in s.as_bytes():
        out.append(b)
    return out^


def _pattern(n: Int) -> List[UInt8]:
    """Deterministic byte pattern: byte i == i % 256 (matches the Python
    cross-check generator `bytes(i % 256 for i in range(n))`)."""
    var out = List[UInt8]()
    for i in range(n):
        out.append(UInt8(i & 0xFF))
    return out^


def _sub(data: List[UInt8], start: Int, end: Int) -> List[UInt8]:
    var out = List[UInt8]()
    for i in range(start, end):
        out.append(data[i])
    return out^


# ── CRC-32 ────────────────────────────────────────────────────────────────


def test_crc32_empty() raises:
    assert_equal(crc32(Span(List[UInt8]())), UInt32(0))


def test_crc32_check_value() raises:
    # Standard CRC-32 check value for the ASCII string "123456789".
    var data = _bytes_of("123456789")
    assert_equal(crc32(Span(data)), UInt32(0xCBF43926))


def test_crc32_incremental_matches_oneshot() raises:
    var a = _bytes_of("hello, ")
    var b = _bytes_of("world!")
    var ab = _bytes_of("hello, world!")
    assert_equal(crc32(Span(ab)), crc32(Span(b), seed=crc32(Span(a))))

    var inc = Crc32()
    inc.update(Span(a))
    inc.update(Span(b))
    assert_equal(inc.finish(), crc32(Span(ab)))


def test_crc32_python_cross_check_100() raises:
    var data = _pattern(100)
    assert_equal(crc32(Span(data)), UInt32(0x58C932F5))


def test_crc32_python_cross_check_1000() raises:
    var data = _pattern(1000)
    assert_equal(crc32(Span(data)), UInt32(0x74E3FB41))


# ── MurmurHash3 x86-32 ───────────────────────────────────────────────────


def test_murmur3_python_cross_check_100() raises:
    var data = _pattern(100)
    assert_equal(murmur3_x86_32(Span(data)), UInt32(0xFC653843))


def test_murmur3_python_cross_check_1000() raises:
    var data = _pattern(1000)
    assert_equal(murmur3_x86_32(Span(data)), UInt32(0x2ABEF0DF))


def test_iceberg_int_34() raises:
    assert_equal(iceberg_hash_int(34), Int32(2017239379))


def test_iceberg_long_34() raises:
    assert_equal(iceberg_hash_long(34), Int32(2017239379))


def test_iceberg_decimal_14_20() raises:
    # unscaled 1420 == 14.20 at scale 2.
    assert_equal(iceberg_hash_decimal(1420), Int32(-500754589))


def test_iceberg_date_2017_11_16() raises:
    # days since epoch.
    assert_equal(iceberg_hash_long(17486), Int32(-653330422))


def test_iceberg_time_22_31_08() raises:
    # microseconds since midnight.
    assert_equal(iceberg_hash_long(81068000000), Int32(-662762989))


def test_iceberg_timestamp_2017_11_16t22_31_08() raises:
    # microseconds since epoch.
    assert_equal(iceberg_hash_long(1510871468000000), Int32(-2047944441))


def test_iceberg_string() raises:
    assert_equal(iceberg_hash_string("iceberg"), Int32(1210000089))


def test_iceberg_uuid() raises:
    # f79c3e09-677c-4bbd-a479-3f349cb785e7
    var hi: UInt64 = 0xF79C3E09677C4BBD
    var lo: UInt64 = 0xA4793F349CB785E7
    assert_equal(iceberg_hash_uuid(hi, lo), Int32(1488055340))


def test_iceberg_bytes() raises:
    var data: List[UInt8] = [0, 1, 2, 3]
    assert_equal(iceberg_hash_bytes(Span(data)), Int32(-188683207))


def test_iceberg_bucket_example() raises:
    # bucket[16] of int 34 -> hash 2017239379, positive so the UInt32 and
    # Int32 bit patterns coincide.
    var h = iceberg_hash_int(34).cast[DType.uint32]()
    assert_equal(iceberg_bucket(h, 16), 2017239379 % 16)


# ── XXH64 ────────────────────────────────────────────────────────────────


def test_xxh64_empty() raises:
    assert_equal(xxh64(Span(List[UInt8]())), UInt64(0xEF46DB3751D8E999))


def test_xxh64_a() raises:
    var data = _bytes_of("a")
    assert_equal(xxh64(Span(data)), UInt64(0xD24EC4F1A98C6E5B))


def test_xxh64_abc() raises:
    var data = _bytes_of("abc")
    assert_equal(xxh64(Span(data)), UInt64(0x44BC2CF5AD770999))


def test_xxh64_python_cross_check_100() raises:
    var data = _pattern(100)
    assert_equal(xxh64(Span(data)), UInt64(0x6AC1E58032166597))


def test_xxh64_python_cross_check_1000() raises:
    var data = _pattern(1000)
    assert_equal(xxh64(Span(data)), UInt64(0x6EF436B00EBA4078))


def test_xxh64_incremental_matches_oneshot_across_boundaries() raises:
    var data = _pattern(200)
    var expected = xxh64(Span(data))

    # Split into odd-sized chunks that straddle the 32-byte block boundary.
    for chunk_size in [1, 3, 7, 31, 32, 33, 64, 200]:
        var h = Xxh64()
        var i = 0
        var n = len(data)
        while i < n:
            var end = i + chunk_size
            if end > n:
                end = n
            var chunk = _sub(data, i, end)
            h.update(Span(chunk))
            i = end
        assert_equal(h.finish(), expected)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
