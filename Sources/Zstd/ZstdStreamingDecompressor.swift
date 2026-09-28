import CZstd
public import CompressionCore

extension Zstd: StreamingDecompressionAlgorithm {
    public struct StreamingDecompressor: CompressionCore.StreamingDecompressor, ~Copyable {
        public let configuration: ZstdDecompressionConfiguration

        @usableFromInline
        var stream: ZstdStreamBox

        @usableFromInline
        var buffer: [UInt8]

        @usableFromInline
        var decompressedBytesCount: Int

        public var isFinished: Bool

        public init(configuration: ZstdDecompressionConfiguration = .default) {
            self.configuration = configuration
            self.decompressedBytesCount = 0
            self.buffer = .init(repeating: 0, count: ZSTD_DStreamOutSize())
            isFinished = false

            self.stream = .decompression()
            unsafe Zstd.preconditionCheck(ZSTD_DCtx_setParameter(stream.value, ZSTD_d_windowLogMax, configuration.windowLogMax))
        }

        deinit {
            unsafe ZSTD_freeDCtx(stream.value)
        }

        @inlinable
        public mutating func decompress(
            _ chunk: Span<UInt8>,
            handler: (Span<UInt8>) throws(Zstd.Error) -> Void
        ) throws(Zstd.Error) {
            var consumed = 0
            var again = true

            var output = self.buffer.mutableSpan

            while again {
                let result = unsafe CZstd_decompressStream(self.stream.value, &output, chunk.extracting(consumed...))
                try Zstd.check(result.status)
                consumed += result.consumed

                decompressedBytesCount += result.produced
                if let max = configuration.maxDecompressedSize, decompressedBytesCount > max {
                    throw .maxDecompressedSizeExceeded
                }

                if result.produced > 0 {
                    try handler(output.span.extracting(..<result.produced))
                }

                if result.produced > 0 || consumed > 0 {
                    isFinished = result.status == 0 && consumed == chunk.count
                }

                again = consumed < chunk.count || (result.produced == output.count && result.status != 0)

                if isFinished, let expectedContentSize = configuration.expectedContentSize {
                    guard decompressedBytesCount == expectedContentSize else {
                        throw .contentSizeMismatch(expected: expectedContentSize, actual: decompressedBytesCount)
                    }
                }
            }
        }
    }
}
