"""Throughput for each hash over a 64 MiB buffer.

    pixi run -e bench bench                    # nightly, table
    pixi run -e bench-stable bench             # stable 1.0.0
    pixi run -e bench bench -- --json          # machine-readable
    pixi run -e bench bench -- --out r.json    # table plus a saved copy
    pixi run -e bench bench -- --only bench_crc32

The buffer is rebuilt on every call rather than shared across benchmarks: the
harness re-enters each body once per phase, and only what is inside `b.iter`
is timed, so construction costs wall-clock but never shows up in the numbers.
"""

from bench import Benchmark, BenchSuite, Metric, keep

from hashes import crc32, murmur3_x86_32, xxh64

comptime SIZE = 64 * 1024 * 1024
"""Buffer size. Large enough that per-call overhead is noise."""


def _make_buffer(n: Int) -> List[UInt8]:
    var out = List[UInt8](capacity=n)
    for i in range(n):
        out.append(UInt8(i & 0xFF))
    return out^


def bench_crc32(mut b: Benchmark) raises:
    var data = _make_buffer(SIZE)
    b.throughput(Metric.bytes(), SIZE)

    @parameter
    def call() raises:
        var h = crc32(Span(data))
        keep(h)

    b.iter[call]()
    keep(data)


def bench_murmur3_x86_32(mut b: Benchmark) raises:
    var data = _make_buffer(SIZE)
    b.throughput(Metric.bytes(), SIZE)

    @parameter
    def call() raises:
        var h = murmur3_x86_32(Span(data))
        keep(h)

    b.iter[call]()
    keep(data)


def bench_xxh64(mut b: Benchmark) raises:
    var data = _make_buffer(SIZE)
    b.throughput(Metric.bytes(), SIZE)

    @parameter
    def call() raises:
        var h = xxh64(Span(data))
        keep(h)

    b.iter[call]()
    keep(data)


def _anchor_call_sites(data: List[UInt8]) raises -> UInt64:
    """Never benchmarked. Exists so each hash has more than one call site.

    `xxh64` is 28% faster when it is the only `xxh64` call in a module -- 40 ms
    per 64 MiB against 51 ms -- because the compiler will specialise it into a
    lone caller and will not when the code is shared. Without this anchor the
    benchmark measures the specialised form, which no consumer that calls
    `xxh64` from two places will ever get, and the published figure would move
    28% the day someone adds a second call. `crc32` and `murmur3_x86_32` are
    unaffected either way; measured, not assumed.
    """
    return (
        UInt64(crc32(Span(data)))
        + UInt64(murmur3_x86_32(Span(data)))
        + xxh64(Span(data))
    )


def main() raises:
    var tiny = _make_buffer(16)
    keep(_anchor_call_sites(tiny))
    BenchSuite.run[__functions_in_module()]()
