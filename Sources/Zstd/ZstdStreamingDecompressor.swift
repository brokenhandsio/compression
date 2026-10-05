import CZstd
public import CompressionCore

extension Zstd: StreamingDecompressionAlgorithm {
    public struct StreamingDecompressor: CompressionCore.StreamingDecompressor, ~Copyable {
        public static var outputBufferSize: Int { ZSTD_DStreamOutSize() }

        public let configuration: ZstdDecompressionConfiguration

        @usableFromInline
        var stream: ZstdStreamBox

        @usableFromInline
        var decompressedBytesCount: Int

        public var isFinished: Bool

        public init(configuration: ZstdDecompressionConfiguration = .default) {
            self.configuration = configuration
            self.decompressedBytesCount = 0
            isFinished = false

            self.stream = .decompression()
            unsafe Zstd.preconditionCheck(ZSTD_DCtx_setParameter(stream.value, ZSTD_d_windowLogMax, configuration.windowLogMax))
        }

        deinit {
            unsafe ZSTD_freeDCtx(stream.value)
        }

        @inlinable
        public mutating func decompress(_ chunk: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Zstd.Error) -> Int {
            var consumed = 0
            var again = true

            while again {
                // Nowhere to write, return so we get a new buffer
                if output.isFull { return consumed }
                // Nothing to compress, request more data
                if chunk.extracting(consumed...).isEmpty { return consumed }

                // We got new bytes and a place to write them:
                // we're not done even if we were before
                self.isFinished = false

                let result = unsafe output.withUnsafeMutableBufferPointer { tail, initialisedCount -> CZstd_StreamResult? in
                    let free = tail.count - initialisedCount
                    guard free > 0, let base = tail.baseAddress else { return nil }

                    let result = unsafe CZstd_decompressStream(
                        self.stream.value,
                        base.advanced(by: initialisedCount),
                        free,
                        chunk.extracting(consumed...)
                    )

                    initialisedCount += result.produced
                    return result
                }
                // Nowhere to write: return so the caller can drain the buffer
                guard let result else { return consumed }

                try Zstd.check(result.status)
                consumed += result.consumed

                decompressedBytesCount += result.produced
                if let max = configuration.maxDecompressedSize, decompressedBytesCount > max {
                    throw .maxDecompressedSizeExceeded
                }

                // Zstd says we're done
                if result.status == 0 {
                    if consumed > chunk.count {
                        preconditionFailure("This should be impossible: we cannot have consumed more bytes than the input has")
                    }

                    // We really are done
                    if consumed == chunk.count {
                        isFinished = true

                        if let expectedContentSize = configuration.expectedContentSize {
                            guard decompressedBytesCount == expectedContentSize else {
                                throw .contentSizeMismatch(expected: expectedContentSize, actual: decompressedBytesCount)
                            }
                        }

                        return consumed
                    }

                    // Not quite done yet: there's more data in the input
                    switch configuration.trailingDataPolicy {
                    case .reject:
                        // If we don't allow for exstra trailing data, throw
                        isFinished = true
                        again = false
                        throw .unexpectedTrailingData

                    case .stop:
                        // If we want to stop after reaching a frame's end, return
                        again = false
                        isFinished = true

                        if let expectedContentSize = configuration.expectedContentSize {
                            guard decompressedBytesCount == expectedContentSize else {
                                throw .contentSizeMismatch(expected: expectedContentSize, actual: decompressedBytesCount)
                            }
                        }

                        return consumed

                    case .concatenate:
                        // If we want to concatenate frames, continue
                        again = true
                        isFinished = false
                    }
                }
            }

            return consumed
        }
    }
}
