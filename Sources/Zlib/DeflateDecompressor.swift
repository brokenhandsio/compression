import CZlib
import CompressionCore

extension Deflate {
    public struct Decompressor: CompressionCore.Decompressor {
        public let configuration: Configuration

        public init(configuration: Configuration = .default) {
            self.configuration = configuration
        }

        public func decompress(_ input: some CompressibleInput) throws -> [UInt8] {
            try input.withSpan { try decompress($0) }
        }

        public func decompress(_ input: Span<UInt8>) throws -> [UInt8] {
            var stream = unsafe z_stream()
            unsafe stream.zalloc = nil
            unsafe stream.zfree = nil
            unsafe stream.opaque = nil

            let rt = unsafe CZlib_inflateInit2(&stream, configuration.format.windowBits)
            switch rt {
            case Z_MEM_ERROR:
                throw Deflate.Error.insufficientMemory
            case Z_OK:
                break
            default:
                throw Deflate.Error.internalError
            }

            defer {
                unsafe CZlib.inflateEnd(&stream)
            }

            var output: [UInt8] = []
            output.reserveCapacity(input.count * 4)

            let chunkSize = 65536
            var chunk = [UInt8](repeating: 0, count: chunkSize)

            unsafe stream.avail_in = UInt32(input.count)
            unsafe stream.next_in = CZlib_voidPtr_to_BytefPtr(input)
            var status: Int32 = Z_OK

            while status != Z_STREAM_END {
                var mutableSpan = chunk.mutableSpan
                unsafe stream.avail_out = UInt32(chunkSize)
                unsafe stream.next_out = CZlib_voidPtr_to_BytefPtr_mut(&mutableSpan)
                status = unsafe CZlib.inflate(&stream, Z_NO_FLUSH)
                let produced = chunkSize - Int(unsafe stream.avail_out)
                output.append(
                    addingCapacity: produced,
                    initializingWith: {
                        for i in 0..<produced { $0.append(mutableSpan[i]) }
                    })

                switch status {
                case Z_OK, Z_STREAM_END: break
                case Z_DATA_ERROR: throw Deflate.Error.corruptData
                case Z_MEM_ERROR: throw Deflate.Error.insufficientMemory
                default: throw Deflate.Error.internalError
                }
            }
            return output
        }
    }
}
