import CZstd
public import CompressionCore

extension Zstd: StreamingCompressionAlgorithm {
    public struct StreamingCompressor: CompressionCore.StreamingCompressor, ~Copyable {
        public static var outputBufferSize: Int { ZSTD_CStreamOutSize() }

        public let configuration: ZstdCompressionConfiguration

        @usableFromInline
        let stream: ZstdStreamBox

        @usableFromInline
        var isFinished: Bool

        public init(configuration: ZstdCompressionConfiguration = .default) {
            self.configuration = configuration
            self.stream = .compression()

            unsafe preconditionCheck(ZSTD_CCtx_setParameter(stream.value, ZSTD_c_strategy, configuration.strategy.rawValue))
            unsafe preconditionCheck(ZSTD_CCtx_setParameter(stream.value, ZSTD_c_compressionLevel, configuration.level.rawValue))

            self.isFinished = false
        }

        deinit {
            unsafe ZSTD_freeCCtx(stream.value)
        }

        @inlinable
        public func compress(_ chunk: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Int {
            var consumed = 0

            while consumed < chunk.count {
                let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount in
                    let free = tail.count - initialisedCount
                    let result = unsafe CZstd_compressStream2(
                        stream.value,
                        tail.baseAddress!.advanced(by: initialisedCount),
                        free,
                        chunk.extracting(consumed...),
                        ZSTD_e_continue
                    )

                    initialisedCount += result.produced
                    return result
                }
                try Zstd.check(result.status)
                consumed += result.consumed
            }

            return consumed
        }

        @inlinable
        public mutating func finish(into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Bool {
            guard !output.isFull else {
                return false
            }

            let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount in
                let free = tail.count - initialisedCount

                let result = unsafe CZstd_compressStream2(
                    stream.value,
                    tail.baseAddress!.advanced(by: initialisedCount),
                    free,
                    Span<UInt8>(),
                    ZSTD_e_end
                )
                initialisedCount += result.produced
                return result
            }

            if try Zstd.check(result.status) == 0 {
                isFinished = true
            }

            return isFinished
        }

        @inlinable
        public mutating func flush(into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Int {
            var status = 1
            var consumed = 0

            let free = output.freeCapacity
            while status != 0 {
                let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount in
                    let result = unsafe CZstd_compressStream2(
                        stream.value,
                        tail.baseAddress!.advanced(by: initialisedCount),
                        free,
                        Span<UInt8>(),
                        ZSTD_e_flush
                    )
                    initialisedCount += result.consumed
                    return result
                }
                status = try Zstd.check(result.status)
                consumed += result.consumed
            }

            return consumed
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
