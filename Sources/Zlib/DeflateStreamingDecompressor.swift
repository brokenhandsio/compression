@preconcurrency @unsafe import CZlib
import CompressionCore

extension Deflate {
    public struct StreamingDecompressor: CompressionCore.StreamingDecompressor, ~Copyable {
        public let configuration: Deflate.DecompressionConfiguration

        @usableFromInline
        var stream: ZStreamBox

        @usableFromInline
        var buffer: [UInt8]

        @usableFromInline
        var decompressedBytesCount: Int

        @usableFromInline
        var _isFinished: Bool
        /// True once end-of-stream has been observed with no input left over.
        /// Resets to `false` when a concatenated stream starts a new member.
        public internal(set) var isFinished: Bool {
            @inlinable
            get { _isFinished }
            @usableFromInline
            set { _isFinished = newValue }
        }

        public init(configuration: Configuration) {
            self.configuration = configuration
            self.stream = .init()
            unsafe stream.value.zalloc = nil
            unsafe stream.value.zfree = nil
            unsafe stream.value.opaque = nil

            let rt = unsafe CZlib_inflateInit2(&stream.value, configuration.format.windowBits)
            precondition(rt == CZLIB_Z_OK, "inflateInit2 failed: \(rt)")

            buffer = unsafe .init(unsafeUninitializedCapacity: 32 * 1024) { _, count in
                count = 32 * 1024
            }

            decompressedBytesCount = 0
            _isFinished = false
        }

        deinit {
            unsafe czlib_z_inflateEnd(&stream.value)
        }

        @inlinable
        public mutating func decompress(
            _ chunk: Span<UInt8>,
            handler: (Span<UInt8>) throws(Deflate.Error) -> Void
        ) throws(Deflate.Error) {
            let streamRef = stream
            unsafe streamRef.value.avail_in = UInt32(chunk.count)
            unsafe streamRef.value.next_in = CZlib_voidPtr_to_BytefPtr(chunk)

            var totalDecompressed = decompressedBytesCount
            let maxDecompressedSize = configuration.maxDecompressedSize
            let allowsConcatenatedStreams = configuration.allowsConcatenatedStreams
            defer { decompressedBytesCount = totalDecompressed }

            loop: repeat {
                var mutableSpan = buffer.mutableSpan
                unsafe streamRef.value.avail_out = UInt32(mutableSpan.count)
                unsafe streamRef.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)

                let status = unsafe czlib_z_inflate(&streamRef.value, CZLIB_Z_NO_FLUSH)
                let produced = mutableSpan.count - Int(unsafe streamRef.value.avail_out)

                totalDecompressed += produced
                if let max = maxDecompressedSize, totalDecompressed > max {
                    throw .maxDecompressedSizeExceeded
                }

                switch status {
                case CZLIB_Z_OK:
                    if produced > 0 {
                        try handler(mutableSpan.span.extracting(..<produced))
                    }
                case CZLIB_Z_STREAM_END:
                    if produced > 0 {
                        try handler(mutableSpan.span.extracting(..<produced))
                    }
                    if unsafe streamRef.value.avail_in > 0 {
                        // Input continues past end-of-stream.
                        guard allowsConcatenatedStreams else {
                            throw .unexpectedTrailingData
                        }
                        // Another member follows: restart and
                        // keep decompressing. Bytes that don't form a valid
                        // stream will fail with corruptData.
                        guard unsafe czlib_z_inflateReset(&streamRef.value) == CZLIB_Z_OK else {
                            throw .internalError
                        }
                        isFinished = false
                    } else {
                        isFinished = true
                        break loop
                    }
                case CZLIB_Z_BUF_ERROR:
                    break loop
                case CZLIB_Z_DATA_ERROR:
                    throw Deflate.Error.corruptData
                case CZLIB_Z_MEM_ERROR:
                    throw Deflate.Error.insufficientMemory
                default:
                    throw unsafe Deflate.Error.fromZlib(status, message: czlib_z_zError(status))
                }
            } while unsafe (streamRef.value.avail_in > 0 || streamRef.value.avail_out == 0)
        }
    }
}
