import CZlib
@_exported import CompressionCore

/// RFC 1950 zlib, RFC 1951 raw deflate, and RFC 1952 gzip, backed by libz.
public enum Deflate:
    CompressionAlgorithm,
    OneShotCompressionAlgorithm,
    OneShotDecompressionAlgorithm,
    StreamingCompressionAlgorithm,
    StreamingDecompressionAlgorithm
{}

extension Deflate {
    /// Stateless, one-shot deflate compressor.
    ///
    /// Each call to `compress` creates and destroys a fresh zlib stream.
    /// For compressing many chunks as part of a single logical stream - where
    /// LZ77 context should carry across boundaries - use `Deflate.StreamingCompressor`.
    public struct Compressor: CompressionCore.Compressor {
        public let configuration: CompressionConfiguration

        public init(configuration: CompressionConfiguration = .default) {
            self.configuration = configuration
        }

        public func upperBound(forInputSize inputSize: Int) -> Int {
            precondition(inputSize >= 0, "inputSize must not be negative, got \(inputSize)")
            // Port of deflateBound

            let fixedLength = inputSize + (inputSize >> 3) + (inputSize >> 8) + (inputSize >> 9) + 4
            let storeLength = inputSize + (inputSize >> 5) + (inputSize >> 7) + (inputSize >> 11) + 7

            let level = configuration.level == .default ? .custom(6) : configuration.level

            let wrapLength =
                switch configuration.format {
                case .raw: 0
                case .zlib: 6
                case .gzip: 18
                }

            let hashBits = Int(configuration.memory.rawValue) + 7
            // w_bits is always 15
            if hashBits != 8 + 7 {
                return (15 <= hashBits && level != .none ? fixedLength : storeLength) + wrapLength
            }

            return inputSize + (inputSize >> 12) + (inputSize >> 14) + (inputSize >> 25) + 13 - 6
                + wrapLength
        }

        public func compress(_ input: some CompressibleInput) throws(Deflate.Error) -> [UInt8] {
            try input.withSpan { span throws(Deflate.Error) in
                let bound = upperBound(forInputSize: span.count)
                return try [UInt8](capacity: bound) { outputSpan throws(Deflate.Error) in
                    try compress(span, into: &outputSpan)
                }
            }
        }

        public func compress(_ input: some CompressibleInput, into output: inout OutputSpan<UInt8>) throws(Deflate.Error) {
            try input.withSpan { span throws(Deflate.Error) in
                try compress(span, into: &output)
            }
        }

        /// Compress `input` in one shot, returning a new buffer.
        ///
        /// The output size is bounded before allocation using `deflateBound`,
        /// so there is exactly one output allocation and a single `deflate` call.
        public func compress(_ input: Span<UInt8>, into output: inout OutputSpan<UInt8>) throws(Deflate.Error) {
            var stream = unsafe czlib_z_stream()
            unsafe stream.zalloc = nil
            unsafe stream.zfree = nil
            unsafe stream.opaque = nil

            let rt = unsafe CZlib_deflateInit2(
                &stream,
                configuration.level.rawValue,
                CZLIB_Z_DEFLATED,
                configuration.format.windowBits,
                configuration.memory.rawValue,
                configuration.strategy.rawValue,
            )
            switch rt {
            case CZLIB_Z_MEM_ERROR: throw .insufficientMemory
            case CZLIB_Z_OK: break
            default: throw .internalError
            }

            defer {
                let rt = unsafe czlib_z_deflateEnd(&stream)
                precondition(rt != CZLIB_Z_STREAM_ERROR, "deflateEnd returned stream error")
            }

            unsafe stream.avail_in = UInt32(input.count)
            unsafe stream.next_in = CZlib_voidPtr_to_BytefPtr(input)

            unsafe try output.withUnsafeMutableBufferPointer { tail, initializedCount throws(Deflate.Error) in
                let free = tail.count - initializedCount
                guard free > 0, let base = tail.baseAddress else { throw .outputBufferTooSmall }
                let dest = unsafe base + initializedCount

                unsafe stream.avail_out = UInt32(free)
                unsafe stream.next_out = CZlib_voidPtr_to_BytefPtr_mut(dest, free)

                let result = unsafe czlib_z_deflate(&stream, CZLIB_Z_FINISH)

                switch result {
                case CZLIB_Z_STREAM_END: break
                case CZLIB_Z_DATA_ERROR: throw .corruptData
                case CZLIB_Z_OK: throw .outputBufferTooSmall  // since we use Z_FINISH
                case CZLIB_Z_BUF_ERROR: throw .outputBufferTooSmall
                case CZLIB_Z_MEM_ERROR: throw .insufficientMemory
                default: throw .internalError
                }

                let written = tail.count - Int(unsafe stream.avail_out)
                initializedCount += written
            }
        }
    }
}
