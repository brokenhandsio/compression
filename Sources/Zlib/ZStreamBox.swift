@preconcurrency @unsafe import CZlib

@safe @usableFromInline final class ZStreamBox: @unchecked Sendable {
    @usableFromInline
    var value: z_stream
    init(value: z_stream) { unsafe self.value = value }
    init() { unsafe value = z_stream() }
}
