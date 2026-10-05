import CZstd

@testable import Zstandard

/// The content size recorded in a frame header, or `nil` when absent/invalid.
func frameContentSize(of compressed: [UInt8]) -> Int? {
    let declared = compressed.span.withUnsafeBufferPointer { src in
        ZSTD_getFrameContentSize(src.baseAddress, src.count)
    }
    guard declared != ZSTD_CONTENTSIZE_UNKNOWN, declared != ZSTD_CONTENTSIZE_ERROR else {
        return nil
    }
    return Int(declared)
}

/// Little-endian spelling of the zstd frame magic number, `0xFD2FB528`.
let zstdMagicNumber: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

let allStrategies: [ZstdCompressionConfiguration.Strategy] = [
    .fast, .dfast, .greedy, .lazy, .lazy2, .btlazy2, .btopt, .btultra, .btultra2,
]

/// Deterministic pseudo-random bytes, so a failure reproduces exactly.
func pseudoRandomBytes(count: Int, seed: UInt64 = 0x5DEE_CE66_D000_0001) -> [UInt8] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 33)
    }
}
