@preconcurrency @unsafe import CZlib
import CompressionCore

extension Deflate {
    public struct StreamingDecompressor: CompressionCore.StreamingDecompressor, ~Copyable {
        public typealias Configuration = Deflate.DecompressionConfiguration

        public let configuration: Deflate.DecompressionConfiguration

        @usableFromInline
        var stream: ZStreamBox

        @usableFromInline
        var buffer: [UInt8]

        @usableFromInline
        var decompressedBytesCount: Int

        @usableFromInline
        var _isFinished: Bool
        /// True once end-of-stream has been observed.
        /// Resets to `false` when a concatenated stream starts a new member.
        public internal(set) var isFinished: Bool {
            @inlinable
            get { _isFinished }
            @usableFromInline
            set { _isFinished = newValue }
        }

        public init(configuration: Configuration = .default) {
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
        @discardableResult
        public mutating func decompress(
            _ chunk: Span<UInt8>,
            into output: inout OutputSpan<UInt8>
        ) throws(Deflate.Error) -> Int {
            unsafe stream.value.avail_in = UInt32(chunk.count)
            unsafe stream.value.next_in = CZlib_voidPtr_to_BytefPtr(chunk)

            var totalDecompressed = decompressedBytesCount
            let maxDecompressedSize = configuration.maxDecompressedSize
            defer { decompressedBytesCount = totalDecompressed }

            loop: repeat {
                if output.isFull {
                    return chunk.count - Int(unsafe stream.value.avail_in)
                }

                let (status, produced) = unsafe try output.withUnsafeMutableBufferPointer { tail, initialisedCount throws(Deflate.Error) in
                    let free = tail.count - initialisedCount

                    unsafe stream.value.avail_out = UInt32(free)
                    unsafe stream.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(tail.baseAddress! + initialisedCount, free)

                    let status = unsafe czlib_z_inflate(&stream.value, CZLIB_Z_NO_FLUSH)
                    let written = unsafe free - Int(stream.value.avail_out)

                    initialisedCount += written
                    return (status, written)
                }

                totalDecompressed += produced
                if let max = maxDecompressedSize, totalDecompressed > max {
                    throw .maxDecompressedSizeExceeded
                }

                switch status {
                case CZLIB_Z_OK: break
                case CZLIB_Z_STREAM_END:
                    if unsafe stream.value.avail_in == 0 {
                        // Stream is done and there's no trailing data
                        _isFinished = true
                        return chunk.count - Int(unsafe stream.value.avail_in)
                    }

                    switch self.configuration.trailingDataPolicy {
                    case .reject:
                        // We're not expecting another member
                        _isFinished = true
                        throw .unexpectedTrailingData

                    case .stop:
                        // There might be trailing bytes we don't care about
                        _isFinished = true
                        return chunk.count - Int(unsafe stream.value.avail_in)

                    case .concatenate:
                        // Another member follows: restart and
                        // keep decompressing. Bytes that don't form a valid
                        // stream will fail with corruptData.
                        guard unsafe czlib_z_inflateReset(&stream.value) == CZLIB_Z_OK else {
                            throw .internalError
                        }
                        _isFinished = false
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
            } while unsafe (stream.value.avail_in > 0 || stream.value.avail_out == 0)

            return chunk.count - Int(unsafe stream.value.avail_in)
        }
    }
}
