@preconcurrency @unsafe import CZlib

@safe @usableFromInline final class ZStreamBox: @unchecked Sendable {
    @usableFromInline
    var value: czlib_z_stream
    init(value: czlib_z_stream) { unsafe self.value = value }
    init() { unsafe value = czlib_z_stream() }
}
