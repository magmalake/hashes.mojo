"""CRC-32 (IEEE 802.3 / zlib / gzip / PNG) — reflected polynomial 0xEDB88320,
init/xorout 0xFFFFFFFF. Table-driven with a slice-by-8 fast path.

`crc32(data, seed=0)` reproduces `zlib.crc32(data)` in Python (and, by
extension, gzip/PNG CRCs). Passing a previous result as `seed` chains across
buffers exactly like zlib's `crc32(buf, crc)`:
`crc32(b, seed=crc32(a)) == crc32(a + b)`.
"""

comptime _POLY: UInt32 = 0xEDB88320
comptime _XOROUT: UInt32 = 0xFFFFFFFF


def _build_tables() -> List[UInt32]:
    """Flat 8x256 slice-by-8 table; table n occupies [n*256, n*256+256)."""
    var t = List[UInt32]()
    for i in range(256):
        var c = UInt32(i)
        for _ in range(8):
            if (c & 1) != 0:
                c = _POLY ^ (c >> 1)
            else:
                c = c >> 1
        t.append(c)
    for n in range(1, 8):
        for i in range(256):
            var prev = t[(n - 1) * 256 + i]
            var val = t[Int(prev & 0xFF)] ^ (prev >> 8)
            t.append(val)
    return t^


def _process(state_in: UInt32, data: Span[UInt8, _], table: Span[UInt32, _]) -> UInt32:
    var crc = state_in
    var n = len(data)
    var i = 0
    while i + 8 <= n:
        var one = (
            UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
        ) ^ crc
        var two = (
            UInt32(data[i + 4])
            | (UInt32(data[i + 5]) << 8)
            | (UInt32(data[i + 6]) << 16)
            | (UInt32(data[i + 7]) << 24)
        )
        crc = (
            table[7 * 256 + Int(one & 0xFF)]
            ^ table[6 * 256 + Int((one >> 8) & 0xFF)]
            ^ table[5 * 256 + Int((one >> 16) & 0xFF)]
            ^ table[4 * 256 + Int((one >> 24) & 0xFF)]
            ^ table[3 * 256 + Int(two & 0xFF)]
            ^ table[2 * 256 + Int((two >> 8) & 0xFF)]
            ^ table[1 * 256 + Int((two >> 16) & 0xFF)]
            ^ table[0 * 256 + Int((two >> 24) & 0xFF)]
        )
        i += 8
    while i < n:
        crc = table[Int((crc ^ UInt32(data[i])) & 0xFF)] ^ (crc >> 8)
        i += 1
    return crc


struct Crc32(Copyable, Movable):
    """Incremental CRC-32. `seed` is the previous crc32 result (0 to start)."""

    var _table: List[UInt32]
    var _state: UInt32  # complemented running crc

    def __init__(out self, seed: UInt32 = 0):
        self._table = _build_tables()
        self._state = seed ^ _XOROUT

    def update(mut self, data: Span[UInt8, _]):
        self._state = _process(self._state, data, Span(self._table))

    def finish(self) -> UInt32:
        return self._state ^ _XOROUT


def crc32(data: Span[UInt8, _], seed: UInt32 = 0) -> UInt32:
    var c = Crc32(seed)
    c.update(data)
    return c.finish()
