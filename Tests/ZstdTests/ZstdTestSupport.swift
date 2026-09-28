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
