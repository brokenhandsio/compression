import CZstd
import CompressionCore

extension CompressionParameters where Self == Zstd.CompressionConfiguration {
    /// zstd framing (RFC 8878).
    public static func zstd(
        level: Zstd.CompressionConfiguration.Level = .default,
        strategy: Zstd.CompressionConfiguration.Strategy = .auto
    ) -> Self {
        .init(strategy: strategy, level: level)
    }
}

extension DecompressionParameters where Self == Zstd.DecompressionConfiguration {
    /// zstd framing (RFC 8878).
    public static func zstd(
        windowLogMax: Int? = nil,
        maxDecompressedSize: Int? = nil,
        expectedContentSize: Int? = nil,
        trailingDataPolicy: TrailingDataPolicy = .concatenate
    ) -> Self {
        .init(
            windowLogMax: windowLogMax,
            maxDecompressedSize: maxDecompressedSize,
            expectedContentSize: expectedContentSize,
            trailingDataPolicy: trailingDataPolicy
        )
    }
}

extension Zstd {
    public struct CompressionConfiguration: CompressionParameters {
        public typealias Algorithm = Zstd

        /// How hard zstd looks for repeated data.
        @nonexhaustive public enum Strategy: Int, Sendable {
            case auto = 0
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
            public let rawValue: Int

            public init(rawValue: Int) {
                self.rawValue = Swift.max(Int(ZSTD_minCLevel()), Swift.min(Int(ZSTD_maxCLevel()), rawValue))
            }

            public init(integerLiteral value: Int) { self.init(rawValue: value) }

            public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

            /// zstd's default (`ZSTD_CLEVEL_DEFAULT`, currently 3).
            public static let `default` = Self(rawValue: Int(ZSTD_CLEVEL_DEFAULT))
            /// Fastest regular level.
            public static let fastest: Self = 1
            /// Slowest, best-ratio level (`ZSTD_maxCLevel()`, currently 22).
            public static let best = Self(rawValue: Int(ZSTD_maxCLevel()))
            /// Most aggressive negative "fast" level (`ZSTD_minCLevel()`).
            public static let min = Self(rawValue: Int(ZSTD_minCLevel()))
            public static let max = best
        }

        public static let `default` = Self()

        public init() {
            self.strategy = .auto
            self.level = .default
        }

        package init(strategy: Strategy, level: Level) {
            self.strategy = strategy
            self.level = level
        }

        public var strategy: Strategy
        public var level: Level
    }

    public struct DecompressionConfiguration: DecompressionParameters {
        public typealias Algorithm = Zstd

        public static let `default` = Self()

        public init() {
            self.windowLogMax = nil
            self.maxDecompressedSize = nil
            self.expectedContentSize = nil
            self.trailingDataPolicy = .concatenate
        }

        package init(
            windowLogMax: Int? = nil,
            maxDecompressedSize: Int? = nil,
            expectedContentSize: Int? = nil,
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
        /// `nil` uses zstd's default maximum.
        public var windowLogMax: Int?
        var effectiveWindowLogMax: Int32 {
            guard let windowLogMax else { return 0 }
            let bounds = ZSTD_dParam_getBounds(ZSTD_d_windowLogMax)
            return Int32(Swift.max(Int(bounds.lowerBound), Swift.min(Int(bounds.upperBound), windowLogMax)))
        }

        public var maxDecompressedSize: Int?
        /// If set, throws when the size of the decompressed content is different.
        /// If `trailingDataPolicy` is `.concatenate`, this will act on the whole content size,
        /// not the single frame, and a smaller total doesn't throw.
        public var expectedContentSize: Int?
        /// This setting configures what to do when we encounter another member
        /// after we're done streaming the first one.
        public var trailingDataPolicy: TrailingDataPolicy
    }
}
