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

        try input.withSpan { span in
            try compressor.compress(span) { chunk in
                compressed.append(span: chunk)
            }
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()

        try compressed.withSpan { span in
            try decompressor.decompress(span) { chunk in
                output.append(span: chunk)
            }
        }

        #expect(output == input)
    }
}

@Suite("Async Sequence")
struct AsyncSequenceTests {
    @Test("Compress then decompress via async sequences")
    func roundTrip() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)

        let compressedStream = makeStream(for: data, chunkSize: 1024).compressed(using: Deflate.self)
        var compressed = [UInt8]()
        for try await chunk in compressedStream {
            compressed.append(contentsOf: chunk)
        }

        let decompressedStream = makeStream(for: compressed, chunkSize: 1024).decompressed(using: Deflate.self)
        var output = [UInt8]()
        for try await chunk in decompressedStream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)
    }

    private func makeStream<Body: Collection & Sendable>(
        for message: Body,
        chunkSize: Int = 16
    ) -> AsyncStream<Body.SubSequence>
    where Body.SubSequence: Sendable & CompressibleInput {
        AsyncStream<Body.SubSequence> { continuation in
            var offset = message.startIndex
            while offset < message.endIndex {
                let endIndex = message.index(offset, offsetBy: chunkSize, limitedBy: message.endIndex) ?? message.endIndex
                continuation.yield(message[offset..<endIndex])
                offset = endIndex
            }
            continuation.finish()
        }
    }
}
