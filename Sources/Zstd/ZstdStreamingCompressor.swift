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
        public mutating func compress(_ chunk: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Int {
            var consumed = 0

            while consumed < chunk.count {
                guard !output.isFull else { return consumed }

                let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount -> CZstd_StreamResult? in
                    let free = tail.count - initialisedCount
                    guard free > 0, let base = tail.baseAddress else { return nil }

                    let result = unsafe CZstd_compressStream2(
                        stream.value,
                        base.advanced(by: initialisedCount),
                        free,
                        chunk.extracting(consumed...),
                        ZSTD_e_continue
                    )

                    initialisedCount += result.produced
                    return result
                }
                // Nowhere to write: the caller has to drain before we can go on.
                guard let result else { return consumed }

                try Zstd.check(result.status)
                consumed += result.consumed
            }

            return consumed
        }

        @inlinable
        public mutating func finish(into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Bool {
            guard !isFinished else { return true }
            guard !output.isFull else { return false }

            let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount -> CZstd_StreamResult? in
                let free = tail.count - initialisedCount
                guard free > 0, let base = tail.baseAddress else { return nil }

                let result = unsafe CZstd_compressStream2(
                    stream.value,
                    base.advanced(by: initialisedCount),
                    free,
                    Span<UInt8>(),
                    ZSTD_e_end
                )
                initialisedCount += result.produced
                return result
            }
            // Nowhere to write: not finished, call again with room.
            guard let result else { return false }

            if try Zstd.check(result.status) == 0 {
                isFinished = true
            }

            return isFinished
        }

        @inlinable
        public mutating func flush(into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Bool {
            guard !output.isFull else { return false }

            let free = output.freeCapacity
            let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount -> CZstd_StreamResult? in

                guard free > 0, let base = tail.baseAddress else { return nil }

                let result = unsafe CZstd_compressStream2(
                    stream.value,
                    base.advanced(by: initialisedCount),
                    free,
                    Span<UInt8>(),
                    ZSTD_e_flush
                )
                initialisedCount += result.produced
                return result
            }
            // Nowhere to write: not flushed, call again with room.
            guard let result else { return false }

            // A flush is complete when the output was not completely filled.
            // Otherwise there would likely be something else to write
            return try Zstd.check(result.status) == 0 && result.produced < free
        }
    }
}

extension Zstd.StreamingCompressor {
    @inlinable
    public mutating func flush(
        handler: (Span<UInt8>) throws(Zstd.Error) -> Void
    ) throws(Zstd.Error) {
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output throws(Zstd.Error) in
            var isFlushed: Bool
            repeat {
                isFlushed = try self.flush(into: &output)
                if !output.isEmpty {
                    try handler(output.span)
                    output.removeAll()
                }
            } while !isFlushed
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
