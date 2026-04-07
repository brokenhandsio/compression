@preconcurrency @unsafe import CZlib
import CompressionCore

extension Deflate {
    public struct StreamingCompressor: CompressionCore.StreamingCompressor, ~Copyable {
        public let configuration: Deflate.Configuration

        @usableFromInline
        let stream: ZStreamBox

        @usableFromInline
        var output: [UInt8]

        public init(configuration: Configuration) throws {
            self.configuration = configuration
            self.stream = .init()
            unsafe stream.value.zalloc = nil
            unsafe stream.value.zfree = nil
            unsafe stream.value.opaque = nil

            let rt = unsafe CZlib_deflateInit2(
                &stream.value,
                configuration.level.rawValue,
                Z_DEFLATED,
                configuration.format.windowBits,
                configuration.memLevel,
                configuration.strategy.rawValue,
            )
            switch rt {
            case Z_MEM_ERROR:
                throw Deflate.Error.insufficientMemory
            case Z_OK:
                break
            default:
                throw Deflate.Error.internalError
            }

            output = .init(repeating: 0, count: 32768)
        }

        deinit {
            unsafe CZlib.deflateEnd(&stream.value)
        }

        @inlinable
        public mutating func compress(
            _ chunk: Span<UInt8>,
            handler: (Span<UInt8>) throws -> Void
        ) throws {
            let streamRef = stream
            unsafe streamRef.value.avail_in = UInt32(chunk.count)
            unsafe streamRef.value.next_in = CZlib_voidPtr_to_BytefPtr(chunk)

            repeat {
                var mutableSpan = output.mutableSpan
                unsafe streamRef.value.avail_out = UInt32(mutableSpan.count)
                unsafe streamRef.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)
                let status = unsafe CZlib.deflate(&streamRef.value, Z_SYNC_FLUSH)
                let produced = mutableSpan.count - Int(unsafe streamRef.value.avail_out)

                switch status {
                case Z_OK, Z_STREAM_END, Z_BUF_ERROR:
                    if produced > 0 {
                        try handler(output.span.extracting(..<produced))
                    }
                case Z_DATA_ERROR:
                    throw Deflate.Error.corruptData
                case Z_MEM_ERROR:
                    throw Deflate.Error.insufficientMemory
                default:
                    throw unsafe Deflate.Error.fromZlib(status, message: zError(status))
                }
            } while unsafe streamRef.value.avail_in > 0
        }

        public mutating func finish(
            handler: (Span<UInt8>) throws -> Void
        ) throws {
            let streamRef = stream
            unsafe streamRef.value.avail_in = 0
            var status: Int32
            repeat {
                var mutableSpan = output.mutableSpan
                unsafe streamRef.value.avail_out = UInt32(mutableSpan.count)
                unsafe streamRef.value.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)
                status = unsafe CZlib.deflate(&streamRef.value, Z_FINISH)

                switch status {
                case Z_OK, Z_STREAM_END:
                    let produced = mutableSpan.count - Int(unsafe streamRef.value.avail_out)
                    if produced > 0 {
                        try handler(output.span.extracting(..<produced))
                    }
                case Z_MEM_ERROR:
                    throw Deflate.Error.insufficientMemory
                default:
                    throw unsafe Deflate.Error.fromZlib(status, message: zError(status))
                }
            } while status != Z_STREAM_END
        }
    }
}
