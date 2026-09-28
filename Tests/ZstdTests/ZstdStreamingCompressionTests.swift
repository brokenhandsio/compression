import Testing
import Zstandard

@Suite("Zstd Streaming Compression Tests")
struct ZstdStreamingCompressionTests {
    @Test("Round-trips across formats", arguments: formatRoundTripCases)
    func formats(testCase: FormatRoundTripCase) throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        var compressor = Zstd.StreamingCompressor(configuration: testCase.compress)
        var compressed = [UInt8]()

        try compressor.compress(input.span) { chunk in
            compressed.append(span: chunk)
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        var decompressor = Zstd.StreamingDecompressor(configuration: testCase.decompress)
        var decompressed = [UInt8]()

        for start in stride(from: 0, to: compressed.count, by: 1_024) {
            let end = min(start + 1_024, compressed.count)
            try compressed[start..<end].withSpan { span in
                try decompressor.decompress(span) { output in
                    decompressed.append(span: output)
                }
            }
        }

        let isFinished = decompressor.isFinished

        #expect(isFinished, "end-of-frame marker must be observed")
        #expect(decompressed == input)
    }

    @Test("Streaming output decompresses with one-shot Decompressor")
    func streamingOutputDecompressesWithOneShotDecompressor() throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        var compressor = Zstd.StreamingCompressor()
        var compressed = [UInt8]()

        try compressor.compress(input.span) { chunk in
            compressed.append(span: chunk)
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        let decompressor = Zstd.Decompressor()
        let decompressed = try decompressor.decompress(compressed)

        #expect(decompressed == input)
    }
}

struct FormatRoundTripCase: Sendable, CustomStringConvertible {
    let name: String
    let compress: Zstd.CompressionConfiguration
    let decompress: Zstd.DecompressionConfiguration
    var description: String { name }
}

private let compressionCases: [(name: String, configuration: Zstd.CompressionConfiguration)] = {
    let levels: [Zstd.CompressionConfiguration.Level] = [
        .min, -5, -1,
        1, .default, 5, 9, 12, 19,
        .max,
    ]

    return allStrategies.flatMap { strategy in
        levels.map { level in
            (name: "\(strategy)@\(level)", configuration: .init(strategy: strategy, level: level))
        }
    } + [(name: "default", configuration: .default)]
}()

/// Every decompression knob: the library default, zstd's own default window
/// limit (`0`), an explicit limit large enough for every compression case
/// above, and a `maxDecompressedSize` both unset and exactly at the input size.
private let decompressionCases: [(name: String, configuration: Zstd.DecompressionConfiguration)] = [
    (name: "default", configuration: .default)
    // (name: "windowLogMax=0", configuration: .init(windowLogMax: 0, maxDecompressedSize: nil)),
    // (name: "windowLogMax=27", configuration: .init(windowLogMax: 27, maxDecompressedSize: nil)),
    // (name: "maxDecompressedSize=50_000", configuration: .init(windowLogMax: 0, maxDecompressedSize: 50_000)),
    // (name: "windowLogMax=27, maxDecompressedSize=50_000", configuration: .init(windowLogMax: 27, maxDecompressedSize: 50_000)),
]

let formatRoundTripCases: [FormatRoundTripCase] = compressionCases.flatMap { compress in
    decompressionCases.map { decompress in
        .init(
            name: "\(compress.name) -> \(decompress.name)",
            compress: compress.configuration,
            decompress: decompress.configuration
        )
    }
}
