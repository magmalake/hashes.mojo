"""Throughput for each hash over a 64 MiB buffer, via `std.benchmark`.

Replaces a hand-rolled harness that timed one call each with `perf_counter_ns`
and kept the results alive by printing them. Three things improve:

- `Bench` warms up, chooses its own batch sizes, and reports a mean over many
  iterations rather than a single cold sample;
- `compiler.keep` says "this value must survive" outright, instead of relying
  on a trailing `print` to stop the optimiser deleting the call;
- `ThroughputMeasure(BenchMetric.bytes, SIZE)` has the harness derive GB/s, so
  the rate is no longer arithmetic done by hand inside the benchmark.

Pass a path to also write the results as CSV:

    pixi run -e stable bench results.csv

**This runs on stable 1.0.0 only.** On nightly, `Bencher.iter` has lost its
parameter form and its value form will not accept a `@parameter` closure,
while a plain closure cannot infer a capture convention at all -- so nightly
`std.benchmark` cannot express a benchmark that closes over data. See the
magmalake `.github` issue on adopting `std.benchmark` for the overload lists.
"""

from std.benchmark import (
    Bench,
    BenchConfig,
    Bencher,
    BenchId,
    BenchMetric,
    Format,
    ThroughputMeasure,
)
from std.benchmark.compiler import keep
from std.os import abort
from std.pathlib import Path
from std.sys import argv

from hashes import crc32, murmur3_x86_32, xxh64

comptime SIZE = 64 * 1024 * 1024
"""Buffer size. Large enough that per-call overhead is noise."""


def _make_buffer(n: Int) -> List[UInt8]:
    var out = List[UInt8](capacity=n)
    for i in range(n):
        out.append(UInt8(i & 0xFF))
    return out^


# Three shapes below are toolchain constraints rather than anything to do with
# hashing, and they are worth naming because the next tin will hit them too:
#
#   * the buffer arrives as `bench_with_input`'s argument, because a closure
#     cannot infer a capture convention for a `Span`;
#   * the inner closure is `@parameter`, because only a `@parameter` closure
#     may capture at all -- hence `b.iter[call]()` rather than `b.iter(call)`;
#   * the benchmark itself does not raise, swallowing an impossible error from
#     the hashes, because the `bench_with_input` overload that takes a plain
#     function by value is the non-raising one.
def bench_crc32(mut b: Bencher, buf: List[UInt8]):
    @parameter
    def call():
        try:
            var h = crc32(Span(buf))
            keep(h)
        except e:
            abort(String(e))

    b.iter[call]()


def bench_murmur3(mut b: Bencher, buf: List[UInt8]):
    @parameter
    def call():
        try:
            var h = murmur3_x86_32(Span(buf))
            keep(h)
        except e:
            abort(String(e))

    b.iter[call]()


def bench_xxh64(mut b: Bencher, buf: List[UInt8]):
    @parameter
    def call():
        try:
            var h = xxh64(Span(buf))
            keep(h)
        except e:
            abort(String(e))

    b.iter[call]()


def main() raises:
    print("building", SIZE // (1024 * 1024), "MiB buffer...")
    var data = _make_buffer(SIZE)

    var config = BenchConfig(
        min_runtime_secs=1.0, max_runtime_secs=5.0, num_warmup_iters=2
    )
    var args = argv()
    if len(args) > 1:
        config.out_file = Path(String(args[1]))
        config.out_file_format = Format.csv

    var m = Bench(config^)
    var bytes = List[ThroughputMeasure]()
    bytes.append(ThroughputMeasure(BenchMetric.bytes, SIZE))

    m.bench_with_input(bench_crc32, BenchId("crc32"), data, bytes)
    m.bench_with_input(bench_murmur3, BenchId("murmur3_x86_32"), data, bytes)
    m.bench_with_input(bench_xxh64, BenchId("xxh64"), data, bytes)

    m.dump_report()
