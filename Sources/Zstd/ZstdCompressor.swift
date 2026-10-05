import CZstd
public import CompressionCore

extension Zstd: OneShotCompressionAlgorithm {
    public struct Compressor: CompressionCore.Compressor {
        public let configuration: ZstdCompressionConfiguration

        public init(configuration: Configuration = .default) {
            self.configuration = configuration
        }

        public func compress(_ input: some CompressionCore.CompressibleInput) throws(Zstd.Error) -> [UInt8] {
            try input.withSpan { inputSpan throws(Zstd.Error) in
                let bound = try Zstd.check(ZSTD_compressBound(inputSpan.count))

                return try [UInt8](capacity: bound) { output throws(Zstd.Error) in
                    try compress(inputSpan, into: &output)
                }
            }
        }

        public func compress(_ input: some CompressionCore.CompressibleInput, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) {
            try input.withSpan { inputSpan throws(Zstd.Error) in
                try compress(inputSpan, into: &output)
            }
        }

        public func compress(_ input: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) {
            guard let cctx = unsafe ZSTD_createCCtx() else { throw .insufficientMemory }
            defer { _ = unsafe ZSTD_freeCCtx(cctx) }

            unsafe try Zstd.check(ZSTD_CCtx_setParameter(cctx, ZSTD_c_strategy, configuration.strategy.rawValue))
            unsafe try Zstd.check(ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, configuration.level.rawValue))

            // `OutputSpan` only exposes a `MutableSpan` over its initialized prefix, so the
            // free capacity still has to be reached through the unsafe buffer pointer.
            try unsafe output.withUnsafeMutableBufferPointer { tail, initCount throws(Zstd.Error) in
                var dst = unsafe MutableSpan(_unsafeElements: tail.extracting(initCount...))
                let status = unsafe CZstd_compress2(cctx, &dst, input)
                try Zstd.check(status)

                initCount += status
            }
        }
    }
}

extension Zstd {
    @inline(__always)
    @usableFromInline
    @discardableResult
    static func check(_ result: Int) throws(Zstd.Error) -> Int {
        guard ZSTD_isError(result) == 0 else {
            throw Zstd.Error(result: result)
        }
        return result
    }
}
