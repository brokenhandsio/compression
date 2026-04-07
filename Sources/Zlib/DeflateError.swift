import CZlib

extension Deflate {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        case insufficientMemory
        case corruptData
        case bufferOverflow
        case internalError
        case zlib(code: Int32, message: String)

        @usableFromInline
        static func fromZlib(_ code: Int32, message: UnsafePointer<CChar>? = nil) -> Self {
            let msg: String
            if let m = unsafe message {
                msg = unsafe String(cString: m)
            } else {
                msg =
                    switch code {
                    case Z_ERRNO: "File I/O error"
                    case Z_STREAM_ERROR: "Stream state inconsistent"
                    case Z_DATA_ERROR: "Invalid or corrupted data"
                    case Z_MEM_ERROR: "Insufficient memory"
                    case Z_BUF_ERROR: "No progress possible"
                    case Z_VERSION_ERROR: "Incompatible zlib version"
                    default: "Unknown zlib error (\(code))"
                    }
            }
            return .zlib(code: code, message: msg)
        }

        public var description: String {
            switch self {
            case .insufficientMemory: "Deflate.Error: insufficient memory"
            case .corruptData: "Deflate.Error: invalid or corrupted data"
            case .bufferOverflow: "Deflate.Error: output buffer too small"
            case .internalError: "Deflate.Error: internal error"
            case .zlib(let code, let message): "Deflate.Error(\(code)): \(message)"
            }
        }
    }

}
