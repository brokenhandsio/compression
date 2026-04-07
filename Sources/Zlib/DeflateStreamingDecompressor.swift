@preconcurrency @unsafe import CZlib
import CompressionCore

extension Deflate {
    public struct StreamingDecompressor: CompressionCore.StreamingDecompressor, ~Copyable {
        public let configuration: Deflate.Configuration

        @usableFromInline
        var stream: ZStreamBox

        @usableFromInline
        var buffer: [UInt8]

        public init(configuration: Configuration) throws {
            self.configuration = configuration
            self.stream = .init()
            unsafe stream.value.zalloc = nil
            unsafe stream.value.zfree = nil
            unsafe stream.value.opaque = nil

            buffer = .init(repeating: 0, count: 32768)

            let rt = unsafe CZlib_inflateInit2(&stream.value, configuration.format.windowBits)
            switch rt {
            case Z_MEM_ERROR:
                throw Deflate.Error.insufficientMemory
            case Z_OK:
                break
            default:
                throw Deflate.Error.internalError
            }
        }

        deinit {
            unsafe CZlib.inflateEnd(&stream.value)
        }

        @inlinable
        public mutating func decompress(_ chunk: Span<UInt8>, handler: (Span<UInt8>) throws -> Void) throws {
            let streamRef = stream
            unsafe streamRef.value.avail_in = UInt32(chunk.count)
            unsafe streamRef.value.next_in = CZlib_voidPtr_to_BytefPtr(chunk)

            repeat {
                var mutableSpan = buffer.mutableSpan
                unsafe streamRef.value.avail_out = UInt32(mutableSpan.count)
                unsafe streamRef.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)

                let status = unsafe CZlib.inflate(&streamRef.value, Z_NO_FLUSH)
                let produced = mutableSpan.count - Int(unsafe streamRef.value.avail_out)

                switch status {
                case Z_OK, Z_STREAM_END:
                    if produced > 0 {
                        try handler(mutableSpan.span.extracting(..<produced))
                    }
                case Z_DATA_ERROR:
                    throw Deflate.Error.corruptData
                case Z_MEM_ERROR:
                    throw Deflate.Error.insufficientMemory
                default:
                    throw unsafe Deflate.Error.fromZlib(status, message: zError(status))
                }
            } while unsafe (streamRef.value.avail_in > 0 || streamRef.value.avail_out == 0)
        }
    }
}
