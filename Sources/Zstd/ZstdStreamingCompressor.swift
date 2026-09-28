import CZstd
public import CompressionCore

extension Zstd: StreamingCompressionAlgorithm {
    public struct StreamingCompressor: CompressionCore.StreamingCompressor, ~Copyable {
        public let configuration: ZstdCompressionConfiguration

        @usableFromInline
        let stream: ZstdStreamBox

        @usableFromInline
        var buffer: [UInt8]

        public init(configuration: ZstdCompressionConfiguration = .default) {
            self.configuration = configuration
            self.stream = .compression()
            self.buffer = .init(repeating: 0, count: ZSTD_CStreamOutSize())

            unsafe preconditionCheck(ZSTD_CCtx_setParameter(stream.value, ZSTD_c_strategy, configuration.strategy.rawValue))
            unsafe preconditionCheck(ZSTD_CCtx_setParameter(stream.value, ZSTD_c_compressionLevel, configuration.level.rawValue))
        }

        deinit {
            unsafe ZSTD_freeCCtx(stream.value)
        }

        public mutating func compress(_ chunk: Span<UInt8>, handler: (Span<UInt8>) throws(Zstd.Error) -> Void) throws(Zstd.Error) {
            var out = buffer.mutableSpan
            var consumed = 0

            while consumed < chunk.count {
                let result = unsafe CZstd_compressStream2(stream.value, &out, chunk.extracting(consumed...), ZSTD_e_continue)
                try Zstd.check(result.status)

                consumed += result.consumed

                if result.produced > 0 {
                    try handler(out.span.extracting(..<result.produced))
                }
            }
        }

        public mutating func flush(handler: (Span<UInt8>) throws(Zstd.Error) -> Void) throws(Zstd.Error) {
            var out = buffer.mutableSpan
            let empty = Span<UInt8>()
            var status = 1

            while status != 0 {
                let result = unsafe CZstd_compressStream2(stream.value, &out, empty, ZSTD_e_flush)
                status = try Zstd.check(result.status)

                if result.produced > 0 {
                    try handler(out.span.extracting(..<result.produced))
                }
            }
        }

        public mutating func finish(handler: (Span<UInt8>) throws(Zstd.Error) -> Void) throws(Zstd.Error) {
            var out = buffer.mutableSpan
            let empty = Span<UInt8>()
            var status = 1

            while status != 0 {
                let result = unsafe CZstd_compressStream2(stream.value, &out, empty, ZSTD_e_end)
                status = try Zstd.check(result.status)

                if result.produced > 0 {
                    try handler(out.span.extracting(..<result.produced))
                }
            }
        }
    }
}

extension Zstd {
    @inline(__always)
    @discardableResult
    static func preconditionCheck(_ result: Int) -> Int {
        guard ZSTD_isError(result) == 0 else {
            preconditionFailure("Zstd errored \(Zstd.Error(result: result))")
        }
        return result
    }
}
