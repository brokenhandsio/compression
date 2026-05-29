import CZlib
import CompressionCore

extension Deflate {
    public struct Decompressor: CompressionCore.Decompressor {
        public let configuration: DecompressionConfiguration

        public init(configuration: DecompressionConfiguration = .default) {
            self.configuration = configuration
        }

        public func decompress(_ input: some CompressibleInput) throws(Deflate.Error) -> [UInt8] {
            var streaming = StreamingDecompressor(configuration: configuration)
            var output = [UInt8]()
            try input.withSpan { span throws(Deflate.Error) in
                output.reserveCapacity(configuration.decompressedSizeHint ?? span.count * 4)
                var total = 0
                try streaming.decompress(span) { produced throws(Deflate.Error) in
                    total += produced.count
                    if let cap = configuration.maxDecompressedSize, total > cap { throw .maxDecompressedSizeExceeded }
                    unsafe output.append(span: produced)
                }
            }
            return output
        }

        public func decompress(_ input: some CompressibleInput, into output: inout OutputSpan<UInt8>) throws(Deflate.Error) {
            try input.withSpan { span throws(Deflate.Error) in
                try decompress(span, into: &output)
            }
        }

        public func decompress(_ input: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Deflate.Error) {
            var stream = unsafe czlib_z_stream()
            unsafe stream.zalloc = nil
            unsafe stream.zfree = nil
            unsafe stream.opaque = nil

            let rt = unsafe CZlib_inflateInit2(&stream, configuration.format.windowBits)
            switch rt {
            case CZLIB_Z_MEM_ERROR: throw .insufficientMemory
            case CZLIB_Z_OK: break
            default: throw .internalError
            }

            defer {
                unsafe czlib_z_inflateEnd(&stream)
            }

            unsafe stream.avail_in = UInt32(input.count)
            unsafe stream.next_in = CZlib_voidPtr_to_BytefPtr(input)
            var status: Int32 = CZLIB_Z_OK

            while status != CZLIB_Z_STREAM_END {
                unsafe try output.withUnsafeMutableBufferPointer { tail, initializedCount throws(Deflate.Error) in
                    let free = tail.count - initializedCount
                    if free == 0 { throw .outputBufferTooSmall }
                    let dest = unsafe tail.baseAddress! + initializedCount

                    unsafe stream.avail_out = UInt32(free)
                    unsafe stream.next_out = CZlib_voidPtr_to_BytefPtr_mut(dest, free)

                    status = unsafe czlib_z_inflate(&stream, CZLIB_Z_NO_FLUSH)
                    let written = free - Int(unsafe stream.avail_out)
                    initializedCount += written

                    switch status {
                    case CZLIB_Z_OK, CZLIB_Z_STREAM_END: break
                    case CZLIB_Z_DATA_ERROR: throw .corruptData
                    case CZLIB_Z_MEM_ERROR: throw .insufficientMemory
                    case CZLIB_Z_BUF_ERROR: throw .outputBufferTooSmall
                    default: throw .internalError
                    }
                }
            }
        }
    }
}
