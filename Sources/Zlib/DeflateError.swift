import CZlib

extension Deflate {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        /// zlib couldn't allocate memory for its internal state.
        case insufficientMemory
        /// Input is not a valid deflate/zlib/gzip stream.
        case corruptData
        /// Caller-supplied `OutputSpan` ran out of room before compression finished.
        case outputBufferTooSmall
        /// Input ended in the middle of a deflate stream. The data is incomplete;
        /// retrying with a larger output buffer will not help — more input is needed.
        case truncatedInput
        /// Input continued past end-of-stream and
        /// `DecompressionConfiguration.allowsConcatenatedStreams` is `false`.
        case unexpectedTrailingData
        /// Output would exceed `DecompressionConfiguration.maxDecompressedSize`.
        case maxDecompressedSizeExceeded
        /// Unexpected zlib state. Indicates a bug in this package.
        case internalError
        /// Raw zlib error code and message, for codes that don't map to one of the above.
        case zlib(code: Int32, message: String)

        @usableFromInline
        static func fromZlib(_ code: Int32, message: UnsafePointer<CChar>? = nil) -> Self {
            let msg: String
            if let m = unsafe message {
                msg = unsafe String(cString: m)
            } else {
                msg =
                    switch code {
                    case CZLIB_Z_ERRNO: "File I/O error"
                    case CZLIB_Z_STREAM_ERROR: "Stream state inconsistent"
                    case CZLIB_Z_DATA_ERROR: "Invalid or corrupted data"
                    case CZLIB_Z_MEM_ERROR: "Insufficient memory"
                    case CZLIB_Z_BUF_ERROR: "No progress possible"
                    case CZLIB_Z_VERSION_ERROR: "Incompatible zlib version"
                    default: "Unknown zlib error (\(code))"
                    }
            }
            return .zlib(code: code, message: msg)
        }

        public var description: String {
            switch self {
            case .insufficientMemory: "Deflate.Error: insufficient memory"
            case .corruptData: "Deflate.Error: invalid or corrupted data"
            case .outputBufferTooSmall: "Deflate.Error: output buffer too small"
            case .truncatedInput: "Deflate.Error: truncated or incomplete input"
            case .unexpectedTrailingData: "Deflate.Error: unexpected trailing data after end of stream"
            case .maxDecompressedSizeExceeded: "Deflate.Error: max decompressed size exceeded"
            case .internalError: "Deflate.Error: internal error"
            case .zlib(let code, let message): "Deflate.Error(\(code)): \(message)"
            }
        }
    }
}
