import CompressionDeflate
import Testing

// MARK: - Streaming Compressor

@Suite("Streaming Compressor")
struct StreamingCompressorTests {
    @Test("Finishing with no input produces valid empty stream")
    func emptyStream() throws {
        var compressor = try Deflate.StreamingCompressor(configuration: .default)
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

        var compressor = try Deflate.StreamingCompressor(configuration: .default)
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

    @Test(
        "Round-trips across formats",
        arguments: [
            Deflate.Configuration.default,
            .gzip,
            .raw,
            .fast,
            .best,
        ])
    func formats(config: Deflate.Configuration) throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        var compressor = try Deflate.StreamingCompressor(configuration: config)
        var compressed = [UInt8]()

        try input.withSpan { span in
            try compressor.compress(span) { chunk in
                compressed.append(span: chunk)
            }
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        #expect(try Deflate.Decompressor(configuration: config).decompress(compressed) == input)
    }
}

// MARK: - Streaming Decompressor

@Suite("Streaming Decompressor")
struct StreamingDecompressorTests {
    @Test("Feed compressed data one byte at a time")
    func byteByByte() throws {
        let input = Array("Byte by byte decompression test!".utf8)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()

        for byte in compressed {
            try [byte].withSpan { span in
                try decompressor.decompress(span) { chunk in
                    output.append(span: chunk)
                }
            }
        }

        #expect(output == input)
    }

    @Test("Large input calls handler multiple times")
    func largeInputMultipleHandlerCalls() throws {
        let input = [UInt8](repeating: 0, count: 1024 * 1024)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()
        output.reserveCapacity(input.count)

        var handlerCallCount = 0
        try compressed.withSpan { span in
            try decompressor.decompress(span) { chunk in
                handlerCallCount += 1
                output.append(span: chunk)
            }
        }

        #expect(output == input)
        #expect(handlerCallCount >= 2)
    }

    @Test("Round-trips across chunk sizes", arguments: [1, 16, 256, 4096, 32768, 65536])
    func chunkSizes(chunkSize: Int) throws {
        let input =
            Array("The quick brown fox jumps over the lazy dog. ".utf8)
            + Array(repeating: UInt8(0x00), count: 100_000)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()
        output.reserveCapacity(input.count)

        var offset = 0
        while offset < compressed.count {
            let end = min(compressed.count, offset + chunkSize)
            try compressed[offset..<end].withSpan { span in
                try decompressor.decompress(span) { chunk in
                    output.append(span: chunk)
                }
            }
            offset = end
        }

        #expect(output == input)
    }

    @Test(
        "Round-trips across formats",
        arguments: [
            Deflate.Configuration.default,
            .gzip,
            .raw,
        ])
    func formats(config: Deflate.Configuration) throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor(configuration: config).compress(input)

        var decompressor = try Deflate.StreamingDecompressor(configuration: config)
        var output = [UInt8]()

        try compressed.withSpan { span in
            try decompressor.decompress(span) { chunk in
                output.append(span: chunk)
            }
        }

        #expect(output == input)
    }

    @Test("Corrupt data throws")
    func corruptDataThrows() throws {
        var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
        let garbage: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC, 0xFB]

        #expect(throws: Deflate.Error.self) {
            try garbage.withSpan { span in
                try decompressor.decompress(span) { _ in }
            }
        }
    }
}

// MARK: - Full streaming round-trip (compress streaming -> decompress streaming)

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

        var compressor = try Deflate.StreamingCompressor(configuration: .default)
        var compressed = [UInt8]()

        try input.withSpan { span in
            try compressor.compress(span) { chunk in
                compressed.append(span: chunk)
            }
        }
        try compressor.finish { chunk in
            compressed.append(span: chunk)
        }

        var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()

        try compressed.withSpan { span in
            try decompressor.decompress(span) { chunk in
                output.append(span: chunk)
            }
        }

        #expect(output == input)
    }
}

// MARK: - Async Sequence

@Suite("Async Sequence")
struct AsyncSequenceTests {
    @Test("Compress then decompress via async sequences")
    func roundTrip() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)

        let compressedStream = try makeStream(for: data, chunkSize: 1024)
            .compressed(using: Deflate.self)
        var compressed = [UInt8]()
        for try await chunk in compressedStream {
            compressed.append(contentsOf: chunk)
        }

        let decompressedStream = try makeStream(for: compressed, chunkSize: 1024)
            .decompressed(using: Deflate.self)
        var output = [UInt8]()
        for try await chunk in decompressedStream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)
    }

    private func makeStream<Body: CompressibleInput>(
        for message: Body,
        chunkSize: Int = 16
    ) -> AsyncStream<Body.SubSequence>
    where Body.SubSequence: Sendable {
        AsyncStream<Body.SubSequence> { continuation in
            var offset = message.startIndex
            while offset < message.endIndex {
                let endIndex = min(message.endIndex, message.index(offset, offsetBy: chunkSize))
                continuation.yield(message[offset..<endIndex])
                offset = endIndex
            }
            continuation.finish()
        }
    }
}

// MARK: - Helpers

extension Array where Element == UInt8 {
    fileprivate mutating func append(span: Span<UInt8>) {
        append(addingCapacity: span.count) {
            for i in 0..<span.count { $0.append(span[i]) }
        }
    }
}
