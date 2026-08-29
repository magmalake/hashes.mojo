"""XXH64 per https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md.

Parquet split-block bloom filters hash column values with XXH64 seed 0.
"""

comptime _P1: UInt64 = 0x9E3779B185EBCA87
comptime _P2: UInt64 = 0xC2B2AE3D27D4EB4F
comptime _P3: UInt64 = 0x165667B19E3779F9
comptime _P4: UInt64 = 0x85EBCA77C2B2AE63
comptime _P5: UInt64 = 0x27D4EB2F165667C5


def _rotl64(x: UInt64, r: Int) -> UInt64:
    return (x << UInt64(r)) | (x >> UInt64(64 - r))


def _round(acc_in: UInt64, input: UInt64) -> UInt64:
    var acc = acc_in
    acc += input * _P2
    acc = _rotl64(acc, 31)
    acc *= _P1
    return acc


def _merge_round(acc_in: UInt64, val_in: UInt64) -> UInt64:
    var acc = acc_in
    var val = _round(UInt64(0), val_in)
    acc ^= val
    acc = acc * _P1 + _P4
    return acc


def _read_u64le(data: Span[UInt8, _], offset: Int) -> UInt64:
    var v: UInt64 = 0
    for i in range(8):
        v |= UInt64(data[offset + i]) << UInt64(8 * i)
    return v


def _read_u32le(data: Span[UInt8, _], offset: Int) -> UInt32:
    var v: UInt32 = 0
    for i in range(4):
        v |= UInt32(data[offset + i]) << UInt32(8 * i)
    return v


struct Xxh64(Copyable, Movable):
    """Incremental XXH64. `update` may be called any number of times before
    `finish`."""

    var seed: UInt64
    var total_len: UInt64
    var v1: UInt64
    var v2: UInt64
    var v3: UInt64
    var v4: UInt64
    var buf: List[UInt8]  # < 32 bytes of data not yet folded into v1..v4

    def __init__(out self, seed: UInt64 = 0):
        self.seed = seed
        self.total_len = 0
        self.v1 = seed + _P1 + _P2
        self.v2 = seed + _P2
        self.v3 = seed
        self.v4 = seed - _P1
        self.buf = List[UInt8]()

    def _process_block(mut self, data: Span[UInt8, _], offset: Int):
        self.v1 = _round(self.v1, _read_u64le(data, offset))
        self.v2 = _round(self.v2, _read_u64le(data, offset + 8))
        self.v3 = _round(self.v3, _read_u64le(data, offset + 16))
        self.v4 = _round(self.v4, _read_u64le(data, offset + 24))

    def update(mut self, data: Span[UInt8, _]):
        self.total_len += UInt64(len(data))
        var n = len(data)
        var i = 0

        if len(self.buf) > 0:
            while len(self.buf) < 32 and i < n:
                self.buf.append(data[i])
                i += 1
            if len(self.buf) == 32:
                var block = self.buf.copy()
                self._process_block(Span(block), 0)
                self.buf.clear()

        while i + 32 <= n:
            self._process_block(data, i)
            i += 32

        while i < n:
            self.buf.append(data[i])
            i += 1

    def finish(self) -> UInt64:
        var h64: UInt64
        if self.total_len >= 32:
            h64 = (
                _rotl64(self.v1, 1)
                + _rotl64(self.v2, 7)
                + _rotl64(self.v3, 12)
                + _rotl64(self.v4, 18)
            )
            h64 = _merge_round(h64, self.v1)
            h64 = _merge_round(h64, self.v2)
            h64 = _merge_round(h64, self.v3)
            h64 = _merge_round(h64, self.v4)
        else:
            h64 = self.seed + _P5

        h64 += self.total_len

        var rem = len(self.buf)
        var i = 0
        while i + 8 <= rem:
            var k1 = _read_u64le(Span(self.buf), i)
            k1 *= _P2
            k1 = _rotl64(k1, 31)
            k1 *= _P1
            h64 ^= k1
            h64 = _rotl64(h64, 27) * _P1 + _P4
            i += 8
        if i + 4 <= rem:
            var k2 = UInt64(_read_u32le(Span(self.buf), i))
            h64 ^= k2 * _P1
            h64 = _rotl64(h64, 23) * _P2 + _P3
            i += 4
        while i < rem:
            h64 ^= UInt64(self.buf[i]) * _P5
            h64 = _rotl64(h64, 11) * _P1
            i += 1

        h64 ^= h64 >> 33
        h64 *= _P2
        h64 ^= h64 >> 29
        h64 *= _P3
        h64 ^= h64 >> 32
        return h64


def xxh64(data: Span[UInt8, _], seed: UInt64 = 0) -> UInt64:
    var h = Xxh64(seed)
    h.update(data)
    return h.finish()
