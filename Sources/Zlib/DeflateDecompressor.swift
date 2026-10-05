import CZlib
import CompressionCore

extension Deflate {
    /// Stateless, one-shot deflate decompressor.
    ///
    /// Each call to `decompress` creates and destroys a fresh zlib stream.
    /// For decompressing many chunks as part of a single logical stream - where
    /// LZ77 context should carry across boundaries - use ``Deflate.StreamingDecompressor``.
    public struct Decompressor: CompressionCore.Decompressor {
        public typealias Configuration = Deflate.DecompressionConfiguration

        public let configuration: Deflate.DecompressionConfiguration

        public init(configuration: Deflate.DecompressionConfiguration = .default) {
            self.configuration = configuration
        }

        public func decompress(_ input: some CompressibleInput) throws(Deflate.Error) -> [UInt8] {
            var streaming = StreamingDecompressor(configuration: configuration)
            var output = [UInt8]()
            try input.withSpan { span throws(Deflate.Error) in
                output.reserveCapacity(configuration.decompressedSizeHint ?? span.count * 4)
                try streaming.decompress(span) { output.append(span: $0) }
            }
            // One-shot: all input was provided, so the stream must have ended.
            guard streaming.isFinished else { throw .truncatedInput }
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

            decode: while true {
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
                    case CZLIB_Z_BUF_ERROR:
                        // inflate made no progress. avail_in == 0 means the stream
                        // ended mid-block (truncated/incomplete input)
                        if unsafe stream.avail_in == 0 {
                            throw .truncatedInput
                        } else {
                            throw .outputBufferTooSmall
                        }
                    default: throw .internalError
                    }
                }

                if status == CZLIB_Z_STREAM_END {
                    if unsafe stream.avail_in == 0 {
                        return
                    }
                    switch configuration.trailingDataPolicy {
                    case .reject:
                        // Input continues past end-of-stream.
                        throw .unexpectedTrailingData

                    case .stop:
                        return

                    case .concatenate:
                        break
                    }

                    // Another member follows: restart and keep
                    // decompressing into the remaining output space.
                    guard unsafe czlib_z_inflateReset(&stream) == CZLIB_Z_OK else {
                        throw .internalError
                    }
                    status = CZLIB_Z_OK
                }
            }
        }
    }
}
