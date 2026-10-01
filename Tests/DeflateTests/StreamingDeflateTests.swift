import CompressionDeflate
import Testing

@Suite("Streaming Round-trip")
struct StreamingRoundTripTests {
    @Test("Incompressible data survives streaming round-trip")
    func incompressibleData() throws {
        var rng: UInt64 = 0x1234_5678_9ABC_DEF0
        var input = [UInt8](repeating: 0, count: 100_000)
        for i in input.indices {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            input[i] = UInt8(rng >> 56)
        }

        var compressor = Deflate.StreamingCompressor(configuration: .default)
        var compressed = [UInt8]()

        try compressor.compress(input.span) { chunk in
            compressed.append(span: chunk)
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)

        var output = [UInt8]()
        var rest = compressed[...]
        while !decompressor.isFinished {
            let piece = try [UInt8](capacity: 64 * 1024) { out throws(Deflate.Error) in
                let consumed = try decompressor.decompress(rest.span, into: &out)
                rest = rest.dropFirst(consumed)
            }
            output += piece
        }

        #expect(output == input)
    }
}
