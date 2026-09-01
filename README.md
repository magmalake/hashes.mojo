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

`pixi run -e bench bench` hashes a 64 MiB buffer with each function through
[bench.mojo](https://github.com/magmalake/bench.mojo), which warms up,
calibrates its own iteration count, and reports the mean of five timed
repetitions. The GB/s column is the harness's figure, not arithmetic done in
the benchmark. Measured on an Apple Silicon Mac (`osx-arm64`, stable Mojo
1.0.0), across consecutive runs:

| hash | throughput | spread across runs |
|---|---|---|
| CRC-32 (slice-by-8) | 1.46 GB/s | 1.45–1.48 |
| MurmurHash3 x86-32 | 1.65 GB/s | 1.64–1.67 |
| XXH64 | 1.28 GB/s | 1.26–1.29 |

CRC-32 and MurmurHash3 come out a little above the figures published before
2026-09-01 (~1.3 / ~1.5 GB/s), which were a single cold pass over a
freshly built buffer. XXH64 is unchanged at ~1.2–1.3. Same code, better
measurement.

Numbers are single-core, non-SIMD scalar implementations — correctness and
portability (identical results on `osx-arm64` and `linux-64`, stable and
nightly Mojo) took priority over squeezing out the last bit of throughput.

### XXH64 is 28% faster when it has exactly one call site

Worth knowing before you quote a number at it. If a module calls `xxh64`
**once**, the compiler specialises it into that caller and a 64 MiB buffer
takes 40 ms — 1.67 GB/s. Add a second `xxh64` call anywhere in the same module
and the shared version is used instead: 51 ms, 1.29 GB/s. `crc32` and
`murmur3_x86_32` show no such effect; that was measured, not assumed.

The table above reports the **shared** figure, because it is what any consumer
calling `xxh64` from more than one place actually gets, and because the
alternative is a published number that moves 28% the day someone adds a call.
`bench/bench_hashes.mojo` keeps a deliberate `_anchor_call_sites` helper to
pin this down; see the comment there.

Every push to `main` re-runs these and appends to a history published at
[magmalake.github.io/hashes.mojo/benchmarks](https://magmalake.github.io/hashes.mojo/benchmarks/).
Those numbers come from a GitHub runner and are slower and noisier than the
table above, which was taken on an M4 — the history is keyed by machine, so
the two are separate series and never averaged together.

Other output modes:

```sh
pixi run -e bench bench -- --json              # machine-readable, with every repetition
pixi run -e bench bench -- --out results.json  # table plus a saved copy
pixi run -e bench bench -- --only bench_xxh64
pixi run -e bench bench -- --list
```

The `bench` environment is on stable Mojo 1.0.0, for a packaging reason rather
than a language one. A precompiled Mojo package (`.mojoc`; `.mojopkg` is the
deprecated spelling) is stamped with the compiler version that produced it and
refused by any other, and magmalake tins build with `mojo-compiler 1.0.0`.
The harness itself is toolchain-agnostic — [bench.mojo's own
CI](https://github.com/magmalake/bench.mojo) runs it on stable and nightly
from source. The library here still tests on both.

## Install as a mojoshelf tin

```sh
pixi shelf add hashes-mojo     # pixi mode (git source dependency)
```

Working with a coding agent? `npx skills add mojoshelf/mojoshelf --skill mojoshelf-consume --yes` teaches it to find and install tins itself — it installs the `shelf` CLI too.

Or as a plain source dependency: `-I ../hashes.mojo/src`, no FFI, no link
flags.

## Test

```sh
pixi run -e stable test    # stable Mojo 1.0.0
pixi run -e default test   # nightly
pixi run -e bench bench    # throughput numbers above
```

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
