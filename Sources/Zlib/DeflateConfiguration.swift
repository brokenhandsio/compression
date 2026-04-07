import CZlib
import CompressionCore

extension Deflate {
    public struct Configuration: CompressionConfiguration {
        public enum Level: Sendable {
            /// zlib default (~level 6). Good balance of speed and compression.
            case `default`
            /// No compression. Output is slightly larger than input (header overhead).
            case none
            /// Fastest compression (level 1). Low CPU, larger output.
            case speed
            /// Best compression (level 9). High CPU, smallest output.
            case best
            /// Explicit level in the range 1–9.
            case custom(Int32)

            var rawValue: Int32 {
                switch self {
                case .default: Z_DEFAULT_COMPRESSION
                case .none: Z_NO_COMPRESSION
                case .speed: Z_BEST_SPEED
                case .best: Z_BEST_COMPRESSION
                case .custom(let v): max(Z_BEST_SPEED, min(Z_BEST_COMPRESSION, v))
                }
            }
        }

        /// Controls framing: zlib header (RFC 1950), raw deflate (RFC 1951), or gzip (RFC 1952).
        public enum Format: Sendable {
            /// zlib-wrapped deflate with Adler-32 checksum. Default.
            case zlib
            /// Raw deflate stream — no header or trailer. Used in e.g. ZIP files.
            case raw
            /// gzip-wrapped deflate with CRC-32 checksum and file metadata.
            case gzip

            var windowBits: Int32 {
                switch self {
                case .zlib: 15
                case .raw: -15
                case .gzip: 31  // 15 + 16
                }
            }
        }

        /// Controls the compression algorithm's trade-offs.
        public enum Strategy: Sendable {
            /// General-purpose. Picks Huffman + LZ77 dynamically.
            case `default`
            /// Pure Huffman entropy coding. Useful for pre-filtered data.
            case huffmanOnly
            /// Run-length encoding. Good for data with long runs (e.g. grayscale images).
            case rle
            /// Forces fixed Huffman codes. Produces a predefined bitstream structure.
            case fixed
            /// Hint that input has been filtered (e.g. delta-coded). Biases toward Huffman.
            case filtered

            var rawValue: Int32 {
                switch self {
                case .default: Z_DEFAULT_STRATEGY
                case .huffmanOnly: Z_HUFFMAN_ONLY
                case .rle: Z_RLE
                case .fixed: Z_FIXED
                case .filtered: Z_FILTERED
                }
            }
        }

        public var level: Level
        public var format: Format
        /// Internal memory usage for compression state. Range 1–9; default 8.
        /// Higher = faster but uses more RAM (level 8 = 128 KB, level 9 = 256 KB).
        public var memLevel: Int32
        public var strategy: Strategy

        public init(
            level: Level = .default,
            format: Format = .zlib,
            memLevel: Int32 = 8,
            strategy: Strategy = .default
        ) {
            self.level = level
            self.format = format
            self.memLevel = memLevel
            self.strategy = strategy
        }

        /// zlib framing, default level. Suitable for general use.
        public static let `default` = Self()
        /// gzip framing, default level. Suitable for HTTP `Content-Encoding: gzip`.
        public static let gzip = Self(format: .gzip)
        /// Raw deflate, no framing. Suitable for ZIP, PNG, etc.
        public static let raw = Self(format: .raw)
        /// Fastest compression (level 1, high memLevel). Prioritises CPU over ratio.
        public static let fast = Self(level: .speed, memLevel: 9)
        /// Best compression (level 9). Prioritises ratio over CPU.
        public static let best = Self(level: .best)
    }
}
