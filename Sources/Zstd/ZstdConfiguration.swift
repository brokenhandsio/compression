import CZstd
import CompressionCore

public struct ZstdCompressionConfiguration: CompressionParameters {
    @nonexhaustive public enum Strategy: Int32, Sendable {
        case fast = 1
        case dfast = 2
        case greedy = 3
        case lazy = 4
        case lazy2 = 5
        case btlazy2 = 6
        case btopt = 7
        case btultra = 8
        case btultra2 = 9
    }

    public struct Level: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByIntegerLiteral {
        public let rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = Swift.max(ZSTD_minCLevel(), Swift.min(ZSTD_maxCLevel(), rawValue))
        }

        public init(integerLiteral value: Int32) {
            self.init(rawValue: value)
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// zstd's default (`ZSTD_CLEVEL_DEFAULT`, currently 3).
        public static let `default` = Self(rawValue: ZSTD_CLEVEL_DEFAULT)
        /// Fastest regular level.
        public static let fastest: Self = 1
        /// Slowest, best-ratio level (`ZSTD_maxCLevel()`, currently 22).
        public static let best = Self(rawValue: ZSTD_maxCLevel())
        /// Most aggressive negative "fast" level (`ZSTD_minCLevel()`).
        public static let min = Self(rawValue: ZSTD_minCLevel())
        public static let max = best
    }

    public static let `default`: ZstdCompressionConfiguration = .init(strategy: .greedy, level: .default)

    public init() {
        self.strategy = .greedy
        self.level = .default
    }

    package init(strategy: Strategy, level: Level) {
        self.strategy = strategy
        self.level = level
    }

    public var strategy: Strategy
    public var level: Level
}

public struct ZstdDecompressionConfiguration: DecompressionParameters {
    public static let `default`: ZstdDecompressionConfiguration = .init(windowLogMax: 0)

    public init() {
        self.windowLogMax = 0
        self.maxDecompressedSize = nil
        self.expectedContentSize = nil
        self.trailingDataPolicy = .concatenate
    }

    package init(
        windowLogMax: Int32, maxDecompressedSize: Int? = nil, expectedContentSize: Int? = nil,
        trailingDataPolicy: TrailingDataPolicy = .concatenate
    ) {
        self.windowLogMax = windowLogMax
        self.maxDecompressedSize = maxDecompressedSize
        self.expectedContentSize = expectedContentSize
        self.trailingDataPolicy = trailingDataPolicy
    }

    /// Select a size limit (in power of 2) beyond which the streaming API will refuse to allocate
    /// memory buffer in order to protect the host from unreasonable memory requirements.
    ///
    /// This parameter is only useful in streaming mode, since no internal buffer is allocated in single-pass mode.
    /// By default, a decompression context accepts window sizes <= (1 << ZSTD_WINDOWLOG_LIMIT_DEFAULT).
    ///
    /// Special: value 0 means "use default maximum windowLog".
    public var windowLogMax: Int32
    public var maxDecompressedSize: Int?
    /// This is only used on the StreamingDecompressor. The OneShotCompressor will take an
    /// `expectedDecompressedSize` parameter in `decompress` as the compressor can be reused.
    /// This won't have any effect if `trailingDataPolicy` is set to `concatenate`.
    public var expectedContentSize: Int?
    /// This setting configures what to do when we encounter another member
    /// after we're done streaming the first one.
    public var trailingDataPolicy: TrailingDataPolicy
}
