import CZlib
import CompressionCore

extension Deflate {
    public struct CompressionConfiguration: CompressionParameters {
        public var level: Level
        public var format: Format
        public var memory: MemoryUsage
        public var strategy: Strategy

        public init() {
            self.level = .default
            self.format = .zlib
            self.memory = .default
            self.strategy = .default
        }

        package init(
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
        public static let fast = Self(level: .fastest, memory: .high)
        /// Best compression (level 9). Prioritises ratio over CPU.
        public static let best = Self(level: .best)
    }

    public struct DecompressionConfiguration: DecompressionParameters {
        /// Deflate format.
        public var format: Format
        /// Maximum amount of data we allow to be decompressed.
        /// This protects against decompression bombs.
        public var maxDecompressedSize: Int?
        /// This setting configures what to do when we encounter another member
        /// after we're done streaming the first one.
        public var trailingDataPolicy: TrailingDataPolicy

        public init() {
            self.format = .zlib
            self.maxDecompressedSize = nil
            self.trailingDataPolicy = .reject
        }

        package init(
            format: Deflate.Format = .zlib,
            maxDecompressedSize: Int? = nil,
            trailingDataPolicy: TrailingDataPolicy = .reject
        ) {
            self.format = format
            self.maxDecompressedSize = maxDecompressedSize
            self.trailingDataPolicy = trailingDataPolicy
        }

        public static let `default` = Self()
        public static let gzip = Self(format: .gzip, trailingDataPolicy: .concatenate)
    }
}

extension Deflate {
    /// zlib compression level, 0 (store only) through 9. Out-of-range values clamp.
    public struct Level: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByIntegerLiteral {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = Swift.max(0, Swift.min(9, rawValue))
        }

        public init(integerLiteral value: Int) { self.init(rawValue: value) }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// No compression. Output is slightly larger than input (header overhead).
        public static let none: Self = 0
        /// Fastest compression. Low CPU, larger output.
        public static let fastest: Self = 1
        /// zlib's default (level 6). Good balance of speed and ratio.
        public static let `default`: Self = 6
        /// Best compression. High CPU, smallest output.
        public static let best: Self = 9
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
    /// zlib `memLevel`, 1 through 9. Out-of-range values clamp.
    public struct MemoryUsage: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByIntegerLiteral {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = Swift.max(1, Swift.min(9, rawValue))
        }

        public init(integerLiteral value: Int) { self.init(rawValue: value) }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// memLevel 3. Suitable for memory-constrained environments
        /// at the cost of noticeably slower compression and a small ratio penalty.
        public static let low: Self = 3
        /// memLevel 8. zlib's default and the recommended choice for almost all use cases.
        public static let `default`: Self = 8
        /// memLevel 9. Slightly faster than `.default` with marginally better ratio.
        public static let high: Self = 9
    }
}
