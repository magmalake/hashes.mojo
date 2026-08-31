# hashes.mojo

[![mojoshelf](https://mojoshelf.org/badge/hashes-mojo.svg)](https://mojoshelf.org/tins/hashes-mojo) [![mojo nightly](https://mojoshelf.org/badge/hashes-mojo/nightly.svg)](https://mojoshelf.org/tins/hashes-mojo)

[![CI](https://github.com/magmalake/hashes.mojo/actions/workflows/ci.yml/badge.svg)](https://github.com/magmalake/hashes.mojo/actions/workflows/ci.yml)

Part of [**magmalake**](https://magmalake.org) — data lake building blocks in Mojo.

A pure-[Mojo](https://www.modular.com/mojo) library of the three hashes that
**Apache Iceberg** and **Apache Parquet** actually need, with no
dependencies and no FFI:

- **CRC-32** (IEEE 802.3 / zlib / gzip / PNG) — deletion-vector checksums,
  Parquet page CRCs, gzip.
- **MurmurHash3 x86-32** (seed 0) — Iceberg's `bucket[N]` partition
  transform.
- **XXH64** (seed 0) — Parquet split-block bloom filters.

Each hash is exactly bit-compatible with its reference implementation
(`zlib.crc32`, `mmh3.hash(..., signed=False)`, `xxhash.xxh64`) — verified
against those libraries directly, not just against the algorithm's public
test vectors.

## API

```mojo
from hashes import (
    Crc32, crc32,
    murmur3_x86_32,
    iceberg_bucket, iceberg_hash_bytes, iceberg_hash_decimal,
    iceberg_hash_int, iceberg_hash_long, iceberg_hash_string,
    iceberg_hash_uuid,
    Xxh64, xxh64,
)
```

| function | signature | notes |
|---|---|---|
| `crc32` | `crc32(data: Span[UInt8], seed: UInt32 = 0) -> UInt32` | table-driven, slice-by-8 fast path; `seed` chains: `crc32(b, seed=crc32(a)) == crc32(a + b)` |
| `Crc32` | `.update(data)`, `.finish() -> UInt32` | incremental form of `crc32` |
| `murmur3_x86_32` | `murmur3_x86_32(data: Span[UInt8], seed: UInt32 = 0) -> UInt32` | MurmurHash3_x86_32, exact (little-endian blocks, tail handling, fmix) |
| `iceberg_hash_int` | `(v: Int32) -> Int32` | promotes to long per spec |
| `iceberg_hash_long` | `(v: Int64) -> Int32` | 8-byte little-endian serialization |
| `iceberg_hash_string` | `(s: StringSlice) -> Int32` | raw UTF-8 bytes |
| `iceberg_hash_bytes` | `(data: Span[UInt8]) -> Int32` | raw bytes, no prefix |
| `iceberg_hash_uuid` | `(hi: UInt64, lo: UInt64) -> Int32` | 16 bytes, big-endian |
| `iceberg_hash_decimal` | `(unscaled: Int64) -> Int32` | minimal two's-complement big-endian bytes (matches Java `BigInteger.toByteArray()`) |
| `iceberg_bucket` | `(hash: UInt32, n: Int) -> Int` | `(hash & 0x7FFFFFFF) % n` |
| `xxh64` | `xxh64(data: Span[UInt8], seed: UInt64 = 0) -> UInt64` | exact per the [XXH64 spec](https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md) |
| `Xxh64` | `.update(data)`, `.finish() -> UInt64` | incremental form of `xxh64`, buffers correctly across arbitrary chunk boundaries |

### Iceberg bucket example

Reproducing the spec's own worked example — `bucket[16]` of the `int` value
`34`:

```mojo
from hashes import iceberg_bucket, iceberg_hash_int

def main():
    var h = iceberg_hash_int(34).cast[DType.uint32]()  # 2017239379
    var bucket = iceberg_bucket(h, 16)                  # 3
```

## Test vectors

All baked into `tests/test_hashes.mojo` as constants; 23 tests, all passing
on stable and nightly.

| input | CRC-32 | MurmurHash3 x86-32 (seed 0) | XXH64 (seed 0) |
|---|---|---|---|
| `""` (empty) | `0x00000000` | — | `0xEF46DB3751D8E999` |
| `"a"` | — | — | `0xD24EC4F1A98C6E5B` |
| `"abc"` | — | — | `0x44BC2CF5AD770999` |
| `"123456789"` | `0xCBF43926` | — | — |
| 100-byte pattern†| `0x58C932F5` | `0xFC653843` | `0x6AC1E58032166597` |
| 1000-byte pattern†| `0x74E3FB41` | `0x2ABEF0DF` | `0x6EF436B00EBA4078` |

† `bytes(i % 256 for i in range(n))`, cross-checked against Python's
`zlib.crc32`, `mmh3.hash(data, seed=0, signed=False)`, and
`xxhash.xxh64(data, seed=0).intdigest()`.

Iceberg [Appendix-B](https://iceberg.apache.org/spec/#appendix-b-32-bit-hash-requirements)
vectors (all `Int32`, two's complement of the `UInt32` hash):

| value | expected |
|---|---|
| `int` 34 | 2017239379 |
| `long` 34 | 2017239379 |
| `decimal` 14.20 (unscaled 1420) | -500754589 |
| `date` 2017-11-16 (17486 days) | -653330422 |
| `time` 22:31:08 (81068000000 µs) | -662762989 |
| `timestamp` 2017-11-16T22:31:08 (1510871468000000 µs) | -2047944441 |
| `string` "iceberg" | 1210000089 |
| `uuid` f79c3e09-677c-4bbd-a479-3f349cb785e7 | 1488055340 |
| `bytes` 00 01 02 03 | -188683207 |

## Performance

`pixi run bench` hashes a 64 MiB buffer with each function. Measured on an
Apple Silicon Mac (`osx-arm64`, stable Mojo 1.0.0):

| hash | throughput |
|---|---|
| CRC-32 (slice-by-8) | ~1.3 GB/s |
| MurmurHash3 x86-32 | ~1.5 GB/s |
| XXH64 | ~1.2 GB/s |

Numbers are single-core, non-SIMD scalar implementations — correctness and
portability (identical results on `osx-arm64` and `linux-64`, stable and
nightly Mojo) took priority over squeezing out the last bit of throughput.

## Install as a mojoshelf tin

```sh
pixi shelf add hashes-mojo     # pixi mode (git source dependency)
```

Or as a plain source dependency: `-I ../hashes.mojo/src`, no FFI, no link
flags.

## Test

```sh
pixi run -e stable test    # stable Mojo 1.0.0
pixi run -e default test   # nightly
pixi run bench              # throughput numbers above
```

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
