import CZlib
@_exported import CompressionCore

public enum Deflate: CompressionAlgorithm {}

extension Deflate {
    /// Stateless, one-shot deflate compressor.
    ///
    /// Each call to `compress` creates and destroys a fresh zlib stream.
    /// For compressing many chunks as part of a single logical stream — where
    /// LZ77 context should carry across boundaries — use `DeflateCompressorStream`.
    public struct Compressor: CompressionCore.Compressor {
        public let configuration: Configuration

        public init(configuration: Configuration = .default) {
            self.configuration = configuration
        }

        public func compress(_ input: some CompressibleInput) throws -> [UInt8] {
            try input.withSpan { span in
                try compress(span)
            }
        }

        /// Compress `input` in one shot, returning a new buffer.
        ///
        /// The output size is bounded before allocation using `deflateBound`,
        /// so there is exactly one output allocation and a single `deflate` call.
        public func compress(_ input: Span<UInt8>) throws(Deflate.Error) -> [UInt8] {
            var stream = unsafe z_stream()
            unsafe stream.zalloc = nil
            unsafe stream.zfree = nil
            unsafe stream.opaque = nil

            let rt = unsafe CZlib_deflateInit2(
                &stream,
                configuration.level.rawValue,
                Z_DEFLATED,
                configuration.format.windowBits,
                configuration.memLevel,
                configuration.strategy.rawValue,
            )
            switch rt {
            case Z_MEM_ERROR: throw .insufficientMemory
            case Z_OK: break
            default: throw .internalError
            }

            defer {
                let rt = unsafe deflateEnd(&stream)
                assert(rt != Z_STREAM_ERROR, "deflateEnd returned stream error")
            }

            let bound = Int(unsafe CZlib.deflateBound(&stream, UInt(input.count)))
            var output = [UInt8](repeating: 0, count: bound)

            var result: Int32 = Z_OK

            unsafe stream.avail_in = UInt32(input.count)
            unsafe stream.next_in = CZlib_voidPtr_to_BytefPtr(input)

            var outputSpan = output.mutableSpan
            unsafe stream.avail_out = UInt32(outputSpan.count)
            unsafe stream.next_out = CZlib_voidPtr_to_BytefPtr_mut(&outputSpan)

            result = unsafe CZlib.deflate(&stream, Z_FINISH)

            switch result {
            case Z_STREAM_END: break
            case Z_DATA_ERROR: throw .corruptData
            case Z_OK: throw .bufferOverflow  // since we use Z_FINISH
            case Z_BUF_ERROR: throw .bufferOverflow
            case Z_MEM_ERROR: throw .insufficientMemory
            default:
                throw .internalError
            }

            let written = bound - Int(unsafe stream.avail_out)
            output.removeSubrange(written...)
            return output
        }
    }
}
