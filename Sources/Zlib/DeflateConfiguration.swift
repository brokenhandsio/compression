import CZlib
import CompressionCore

extension Deflate {
    public struct CompressionConfiguration: CompressionParameters {
        public var level: Level
        public var format: Format
        public var memory: MemoryUsage
        public var strategy: Strategy

        public init(
            level: Level = .default,
            format: Format = .zlib,
            memory: MemoryUsage = .default,
            strategy: Strategy = .default
        ) {
            self.level = level
            self.format = format
            self.memory = memory
            self.strategy = strategy
        }

        /// zlib framing, default level. Suitable for general use.
        public static let `default` = Self()
        /// gzip framing, default level. Suitable for HTTP `Content-Encoding: gzip`.
        public static let gzip = Self(format: .gzip)
        /// Raw deflate, no framing. Suitable for ZIP, PNG, etc.
        public static let raw = Self(format: .raw)
        /// Fastest compression (level 1, high memory). Prioritises CPU over ratio.
        public static let fast = Self(level: .speed, memory: .high)
        /// Best compression (level 9). Prioritises ratio over CPU.
        public static let best = Self(level: .best)
    }

    public struct DecompressionConfiguration: CompressionParameters {
        public let format: Format
        public let maxDecompressedSize: Int?
        /// Initial capacity hint for the output buffer. Doesn't constrain the result.
        public let decompressedSizeHint: Int?

        public init(
            format: Deflate.Format = .zlib,
            maxDecompressedSize: Int? = nil,
            decompressedSizeHint: Int? = nil
        ) {
            self.format = format
            self.maxDecompressedSize = maxDecompressedSize
            self.decompressedSizeHint = decompressedSizeHint
        }

        public static let `default` = Self()
        public static let gzip = Self(format: .gzip)
    }
}

extension Deflate {
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
            case .default: CZLIB_Z_DEFAULT_COMPRESSION
            case .none: CZLIB_Z_NO_COMPRESSION
            case .speed: CZLIB_Z_BEST_SPEED
            case .best: CZLIB_Z_BEST_COMPRESSION
            case .custom(let v): max(CZLIB_Z_BEST_SPEED, min(CZLIB_Z_BEST_COMPRESSION, v))
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
            case .default: CZLIB_Z_DEFAULT_STRATEGY
            case .huffmanOnly: CZLIB_Z_HUFFMAN_ONLY
            case .rle: CZLIB_Z_RLE
            case .fixed: CZLIB_Z_FIXED
            case .filtered: CZLIB_Z_FILTERED
            }
        }
    }

    /// Controls how much memory the deflate compressor allocates for its
    /// internal LZ77 state. Higher values compress slightly better and run faster,
    /// at the cost of RAM.
    public enum MemoryUsage: Sendable {
        /// memLevel 3: Suitable for memory-constrained environments
        /// at the cost of noticeably slower compression and a small ratio penalty.
        case low
        /// memLevel 8. zlib's default and the
        /// recommended choice for almost all use cases.
        case `default`
        /// memLevel 9. Slightly faster than `.default`
        /// with marginally better ratio. Pick when you compress many buffers
        /// in tight succession and the extra RAM isn't a concern.
        case high
        /// Explicit `memLevel` in the range 1–9. Values outside the range are
        /// clamped to the nearest endpoint.
        case custom(Int32)

        var rawValue: Int32 {
            switch self {
            case .low: 3
            case .default: 8
            case .high: 9
            case .custom(let value): max(1, min(9, value))
            }
        }
    }
}
