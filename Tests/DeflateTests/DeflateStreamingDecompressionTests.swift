import CompressionDeflate
import Testing

@Suite("Deflate Streaming Decompression Tests")
struct DeflateStreamingDecompressionTests {
    @Test("Feed compressed data one byte at a time")
    func byteByByte() throws {
        let input = Array("Byte by byte decompression test!".utf8)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()

        for byte in compressed {
            try decompressor.decompress([byte].span) { chunk in
                output.append(span: chunk)
            }
        }

        #expect(output == input)
    }

    @Test("Large input calls handler multiple times")
    func largeInputMultipleHandlerCalls() throws {
        let input = [UInt8](repeating: 0, count: 1024 * 1024)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()
        output.reserveCapacity(input.count)

        var handlerCallCount = 0
        try decompressor.decompress(compressed.span) { chunk in
            handlerCallCount += 1
            output.append(span: chunk)
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

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()
        output.reserveCapacity(input.count)

        var offset = 0
        while offset < compressed.count {
            let end = min(compressed.count, offset + chunkSize)
            try decompressor.decompress(compressed[offset..<end].span) { chunk in
                output.append(span: chunk)
            }
            offset = end
        }

        #expect(output == input)
    }

    @Test("Round-trips across formats", arguments: formatRoundTripCases)
    func formats(testCase: FormatRoundTripCase) throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor(configuration: testCase.compress).compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: testCase.decompress)
        var output = [UInt8]()

        try decompressor.decompress(compressed.span) { chunk in
            output.append(span: chunk)
        }

        #expect(output == input)
    }

    @Test("Corrupt data throws")
    func corruptDataThrows() throws {
        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        let garbage: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC, 0xFB]

        #expect(throws: Deflate.Error.self) {
            try garbage.withSpan { span in
                try decompressor.decompress(span) { _ in }
            }
        }
    }

    @Test("Empty chunk is a no-op")
    func emptyChunkNoOp() throws {
        let input = Array("data after an empty chunk".utf8)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        var output = [UInt8]()

        try decompressor.decompress([UInt8]().span) { _ in
            Issue.record("handler must not be called for an empty chunk")
        }
        do {
            let finished = decompressor.isFinished
            #expect(!finished)
        }

        try decompressor.decompress(compressed.span) { chunk in
            output.append(span: chunk)
        }
        #expect(output == input)
        do {
            let finished = decompressor.isFinished
            #expect(finished)
        }
    }

    @Test("maxDecompressedSize is enforced on the streaming path")
    func maxDecompressedSizeStreaming() throws {
        let input = [UInt8](repeating: 0, count: 100_000)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(
            configuration: .init(maxDecompressedSize: 1_024)
        )
        #expect(throws: Deflate.Error.maxDecompressedSizeExceeded) {
            try compressed.withSpan { span in
                try decompressor.decompress(span) { _ in }
            }
        }
    }

    @Test("maxDecompressedSize accumulates across chunks")
    func maxDecompressedSizeAcrossChunks() throws {
        let input = [UInt8](repeating: 0, count: 100_000)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(
            configuration: .init(maxDecompressedSize: 1_024)
        )
        #expect(throws: Deflate.Error.maxDecompressedSizeExceeded) {
            for byte in compressed {
                try decompressor.decompress([byte].span) { _ in }
            }
        }
    }
}

@Suite("Stream Termination")
struct StreamTerminationTests {
    @Test("Truncated input leaves isFinished false")
    func truncatedStreaming() throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor().compress(input)
        let truncated = Array(compressed[..<(compressed.count / 2)])

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        try decompressor.decompress(truncated.span) { _ in }
        do {
            let finished = decompressor.isFinished
            #expect(!finished)
        }
    }

    @Test("Concatenated gzip members split across chunks")
    func concatenatedGzipMembersChunked() throws {
        let first = Array("first member, ".utf8)
        let second = Array("second member".utf8)
        let compressor = Deflate.Compressor(configuration: .gzip)
        let compressed = try compressor.compress(first) + compressor.compress(second)

        var decompressor = Deflate.StreamingDecompressor(configuration: .gzip)
        var output = [UInt8]()
        for byte in compressed {
            try decompressor.decompress([byte].span) { chunk in
                output.append(span: chunk)
            }
        }
        #expect(output == first + second)
        do {
            let finished = decompressor.isFinished
            #expect(finished)
        }
    }

    @Test(
        "End of stream inside a later chunk reports the bytes consumed",
        arguments: trailingDataFormatCases, [1, 4, 8, 64]
    )
    func endOfStreamInsideLaterChunk(testCase: FormatRoundTripCase, streamBytesInSecondChunk: Int) throws {
        let input = Array(repeating: Array("The quick brown fox jumps over the lazy dog. ".utf8), count: 200)
            .flatMap { $0 }
        let compressed = try Deflate.Compressor(configuration: testCase.compress).compress(input)
        let trailer: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]

        let split = compressed.count - streamBytesInSecondChunk
        let firstChunk = Array(compressed[..<split])
        let secondChunk = Array(compressed[split...]) + trailer

        var decompressor = Deflate.StreamingDecompressor(configuration: testCase.decompress)
        var output = [UInt8]()

        let firstConsumed = try decompressor.decompress(firstChunk.span) { chunk in
            output.append(span: chunk)
        }
        #expect(firstConsumed == firstChunk.count)
        do {
            let finished = decompressor.isFinished
            #expect(!finished)
        }

        let secondConsumed = try decompressor.decompress(secondChunk.span) { chunk in
            output.append(span: chunk)
        }
        #expect(secondConsumed == streamBytesInSecondChunk)
        #expect(Array(secondChunk[secondConsumed...]) == trailer)
        #expect(output == input)
        do {
            let finished = decompressor.isFinished
            #expect(finished)
        }
    }

    @Test("Decompressing the whole stream returns correct count")
    func decompressingWholeStreamCount() throws {
        let input = Array("The quick brown fox jumps over the lazy dog. ".utf8)
        let compressed = try Deflate.Compressor().compress(input)

        var output = Deflate.StreamingDecompressor()
        #expect(try output.decompress(compressed.span) { _ in } == compressed.count)
    }

    @Test("Decompressing various chunk sizes returns correct count", arguments: [1, 16, 256, 4096, 32768, 65536])
    func decompressingVariousChunkSizesCount(chunkSize: Int) throws {
        let input =
            Array("The quick brown fox jumps over the lazy dog. ".utf8)
            + Array(repeating: UInt8(0x00), count: 100_000)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor()

        var offset = 0
        var sum = 0
        while offset < compressed.count {
            let end = min(compressed.count, offset + chunkSize)
            let decompressed = try decompressor.decompress(compressed[offset..<end].span) { _ in }
            #expect(decompressed == end - offset)
            sum += decompressed
            offset = end
        }

        #expect(sum == compressed.count)
    }

    @Test("Decompressing stream + tail bytes returns correct count")
    func decompressingStreamPlusTailBytesCount() throws {
        let input = Array("The quick brown fox jumps over the lazy dog. ".utf8)
        let compressed = try Deflate.Compressor().compress(input)
        let trailingBytes = [UInt8](repeating: .random(in: 0..<255), count: 100)
        let compressedWithTrailingBytes = compressed + trailingBytes

        var decompressor = Deflate.StreamingDecompressor(configuration: .init(trailingDataPolicy: .stop))
        var output = [UInt8]()

        let consumed = try decompressor.decompress(compressedWithTrailingBytes.span) {
            result in output.append(span: result)
        }
        #expect(consumed == compressed.count)
        #expect(compressedWithTrailingBytes[consumed...] == trailingBytes[...])

        #expect(try decompressor.decompress(trailingBytes.span) { _ in } == 0)
    }
}

/// Formats decompressed with `.stop`. Bytes after the actual stream are left unconsumed.
let trailingDataFormatCases: [FormatRoundTripCase] = [
    .init(name: "zlib", compress: .default, decompress: .init(trailingDataPolicy: .stop)),
    .init(
        name: "gzip",
        compress: .gzip,
        decompress: .init(format: .gzip, trailingDataPolicy: .stop)
    ),
    .init(
        name: "raw",
        compress: Deflate.CompressionConfiguration(format: .raw),
        decompress: .init(format: .raw, trailingDataPolicy: .stop)
    ),
]
