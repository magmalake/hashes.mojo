"""Throughput benchmark: MB/s for each hash over a 64 MiB buffer."""

from std.time import perf_counter_ns

from hashes import crc32, murmur3_x86_32, xxh64

comptime SIZE = 64 * 1024 * 1024


def _make_buffer(n: Int) -> List[UInt8]:
    var out = List[UInt8]()
    for i in range(n):
        out.append(UInt8(i & 0xFF))
    return out^


def _report(name: String, nbytes: Int, ns: Int):
    var seconds = Float64(ns) / 1.0e9
    var mb = Float64(nbytes) / (1024.0 * 1024.0)
    var mb_per_s = mb / seconds
    print(name, "-", mb_per_s, "MB/s (", seconds, "s for", mb, "MiB)")


def main() raises:
    print("Building", SIZE // (1024 * 1024), "MiB buffer...")
    var data = _make_buffer(SIZE)
    var span = Span(data)

    var t0 = perf_counter_ns()
    var c = crc32(span)
    var t1 = perf_counter_ns()
    _report("crc32", SIZE, t1 - t0)

    var t2 = perf_counter_ns()
    var m = murmur3_x86_32(span)
    var t3 = perf_counter_ns()
    _report("murmur3_x86_32", SIZE, t3 - t2)

    var t4 = perf_counter_ns()
    var x = xxh64(span)
    var t5 = perf_counter_ns()
    _report("xxh64", SIZE, t5 - t4)

    # Prevent the optimizer from eliding the calls above.
    print("checksums:", c, m, x)
