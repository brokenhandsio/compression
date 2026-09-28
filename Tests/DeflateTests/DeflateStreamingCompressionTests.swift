import CompressionDeflate
import Testing

@Suite("Deflate Streaming Compressor")
struct DeflateStreamingCompressorTests {
    @Test("Finishing with no input produces valid empty stream")
    func emptyStream() throws {
        var compressor = Deflate.StreamingCompressor(configuration: .default)
        var output = [UInt8]()
        try compressor.finish { span in
            output.append(span: span)
        }
        #expect(try Deflate.Decompressor().decompress(output) == [])
    }

    @Test("Round-trips across chunk sizes", arguments: [1, 16, 256, 4096, 32768, 65536])
    func chunkSizes(chunkSize: Int) throws {
        let input =
            Array("The quick brown fox jumps over the lazy dog. ".utf8)
            + Array(repeating: UInt8(0x00), count: 10_000)

        var compressor = Deflate.StreamingCompressor(configuration: .default)
        var compressed = [UInt8]()

        var offset = 0
        while offset < input.count {
            let end = min(input.count, offset + chunkSize)
            try input[offset..<end].withSpan { span in
                try compressor.compress(span) { chunk in
                    compressed.append(span: chunk)
                }
            }
            offset = end
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        #expect(try Deflate.Decompressor().decompress(compressed) == input)
    }

    @Test("Round-trips across formats", arguments: formatRoundTripCases)
    func formats(testCase: FormatRoundTripCase) throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        var compressor = Deflate.StreamingCompressor(configuration: testCase.compress)
        var compressed = [UInt8]()

        try input.withSpan { span in
            try compressor.compress(span) { chunk in
                compressed.append(span: chunk)
            }
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        let decompressed = try Deflate.Decompressor(configuration: testCase.decompress).decompress(compressed)
        #expect(decompressed == input)
    }

    @Test("Streaming output size matches one-shot", arguments: [256, 4_096, 32_768])
    func streamingMatchesOneShot(chunkSize: Int) throws {
        let unit = Array("The quick brown fox jumps over the lazy dog. ".utf8)
        let input = Array(repeating: unit, count: 2_000).flatMap { $0 }

        let oneShot = try Deflate.Compressor().compress(input)

        var compressor = Deflate.StreamingCompressor(configuration: .default)
        var streaming = [UInt8]()
        var offset = 0
        while offset < input.count {
            let end = min(input.count, offset + chunkSize)
            try input[offset..<end].withSpan { span in
                try compressor.compress(span) { chunk in
                    streaming.append(span: chunk)
                }
            }
            offset = end
        }
        try compressor.finish { chunk in streaming.append(span: chunk) }

        let tolerance = max(64, oneShot.count / 100)
        #expect(
            streaming.count <= oneShot.count + tolerance,
            "streaming=\(streaming.count) one-shot=\(oneShot.count) tolerance=\(tolerance)"
        )
    }

    @Test("Flush produces a recoverable boundary")
    func flushBoundary() throws {
        let firstHalf = Array("The quick brown fox jumps over the lazy dog.".utf8)
        let secondHalf = Array(" Pack my box with five dozen liquor jugs.".utf8)

        var compressor = Deflate.StreamingCompressor(configuration: .default)
        var output = [UInt8]()
        try firstHalf.withSpan { span in
            try compressor.compress(span) { chunk in output.append(span: chunk) }
        }
        try compressor.flush { chunk in output.append(span: chunk) }

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        var recovered = [UInt8]()
        try output.withSpan { span in
            try decompressor.decompress(span) { chunk in recovered.append(span: chunk) }
        }
        #expect(recovered == firstHalf)

        // The compressor must still be usable after flush
        try secondHalf.withSpan { span in
            try compressor.compress(span) { chunk in output.append(span: chunk) }
        }
        try compressor.finish { chunk in output.append(span: chunk) }

        let full = try Deflate.Decompressor().decompress(output)
        #expect(full == firstHalf + secondHalf)
    }

    @Test("Flush is safe with no input and is idempotent")
    func flushIdempotent() throws {
        var compressor = Deflate.StreamingCompressor(configuration: .default)
        var output = [UInt8]()
        try compressor.flush { chunk in output.append(span: chunk) }
        try compressor.flush { chunk in output.append(span: chunk) }

        let payload = Array("done".utf8)
        try payload.withSpan { span in
            try compressor.compress(span) { chunk in output.append(span: chunk) }
        }
        try compressor.finish { chunk in output.append(span: chunk) }

        #expect(try Deflate.Decompressor().decompress(output) == payload)
    }
}

struct FormatRoundTripCase: Sendable, CustomStringConvertible {
    let name: String
    let compress: Deflate.CompressionConfiguration
    let decompress: Deflate.DecompressionConfiguration
    var description: String { name }
}

let formatRoundTripCases: [FormatRoundTripCase] = [
    .init(name: "zlib/default", compress: .default, decompress: .default),
    .init(name: "gzip", compress: .gzip, decompress: .gzip),
    .init(
        name: "raw",
        compress: Deflate.CompressionConfiguration(format: .raw),
        decompress: .init(format: .raw)
    ),
    .init(name: "zlib/fast", compress: .fast, decompress: .default),
    .init(name: "zlib/best", compress: .best, decompress: .default),
]
