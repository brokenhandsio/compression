import CZstd

@safe @usableFromInline struct ZstdStreamBox: ~Copyable, @unchecked Sendable {
    @usableFromInline
    var value: OpaquePointer

    init(value: OpaquePointer) {
        unsafe self.value = value
    }

    /// A `ZSTD_CCtx*`. Free with `ZSTD_freeCCtx`.
    static func compression() -> Self {
        unsafe .init(value: ZSTD_createCCtx())
    }

    /// A `ZSTD_DCtx*`. Free with `ZSTD_freeDCtx`.
    static func decompression() -> Self {
        unsafe .init(value: ZSTD_createDCtx())
    }
}
