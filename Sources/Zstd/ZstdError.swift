import CZstd

extension Zstd {
    /// Errors thrown by the zstd compressor and decompressor.
    ///
    /// The named cases are the failures a caller can distinguish and react to.
    /// Everything else zstd can report is folded into ``zstd(code:message:)``,
    /// which carries the raw `ZSTD_ErrorCode` and zstd's own message for it.
    public enum Error: Swift.Error, CustomStringConvertible, Hashable, Sendable {
        /// zstd couldn't allocate a context or its working memory.
        case insufficientMemory
        /// Input is not a valid zstd frame, or its payload or checksum is corrupt.
        case corruptData
        /// Frame declares a window larger than `DecompressionConfiguration.windowLogMax`
        /// permits. Raise the limit if the input is trusted.
        case windowTooLarge
        /// Input ended before the frame did. The data is incomplete;
        /// retrying with a larger output buffer will not help — more input is needed.
        case truncatedInput
        /// Caller-supplied `OutputSpan` ran out of room before the operation finished.
        case outputBufferTooSmall
        /// Output would exceed `DecompressionConfiguration.maxDecompressedSize`.
        case maxDecompressedSizeExceeded
        /// Frame header doesn't record the content size, so a one-shot output
        /// buffer can't be sized up front. Use the streaming decompressor instead.
        case unknownContentSize
        /// The decompressed byte count is not the same as the expected one.
        case contentSizeMismatch(expected: Int, actual: Int)
        /// Any other zstd failure. `code` is the `ZSTD_ErrorCode`; `message` is
        /// what `ZSTD_getErrorString` reports for it.
        case zstd(code: ZSTD_ErrorCode, message: String)

        /// Map a `ZSTD_ErrorCode` onto the named cases, falling back to ``zstd(code:message:)``.
        public init(_ code: ZSTD_ErrorCode) {
            switch code {
            case ZSTD_error_memory_allocation:
                self = .insufficientMemory
            case ZSTD_error_prefix_unknown,
                ZSTD_error_version_unsupported,
                ZSTD_error_frameParameter_unsupported,
                ZSTD_error_corruption_detected,
                ZSTD_error_checksum_wrong,
                ZSTD_error_literals_headerWrong:
                self = .corruptData
            case ZSTD_error_frameParameter_windowTooLarge:
                self = .windowTooLarge
            case ZSTD_error_srcSize_wrong:
                self = .truncatedInput
            case ZSTD_error_dstSize_tooSmall:
                self = .outputBufferTooSmall
            default:
                // zstd ships the message strings, so there's nothing to keep in sync.
                self = .zstd(code: code, message: unsafe String(cString: ZSTD_getErrorString(code)))
            }
        }

        /// Wrap the error carried by any `size_t` zstd return value.
        ///
        /// Only meaningful when `ZSTD_isError(result)` is non-zero.
        public init(result: Int) {
            self.init(ZSTD_getErrorCode(result))
        }

        public var description: String {
            switch self {
            case .insufficientMemory: "Zstd.Error: insufficient memory"
            case .corruptData: "Zstd.Error: invalid or corrupted data"
            case .windowTooLarge: "Zstd.Error: frame window exceeds windowLogMax"
            case .truncatedInput: "Zstd.Error: truncated or incomplete input"
            case .outputBufferTooSmall: "Zstd.Error: output buffer too small"
            case .maxDecompressedSizeExceeded: "Zstd.Error: max decompressed size exceeded"
            case .unknownContentSize: "Zstd.Error: frame does not declare its content size"
            case .contentSizeMismatch(let expected, let actual):
                "Zstd.Error: expected content size (\(expected)) does not match actual (\(actual))"
            case .zstd(let code, let message): "Zstd.Error(\(code.rawValue)): \(message)"
            }
        }
    }
}
