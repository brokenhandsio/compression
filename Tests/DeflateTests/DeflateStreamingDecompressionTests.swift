import CompressionDeflate
import Testing

@Suite("Deflate Streaming Decompressor")
struct DeflateStreamingDecompressorTests {
    @Test("Feed compressed data one byte at a time")
    func byteByByte() throws {
        let input = Array("Byte by byte decompression test!".utf8)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
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

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
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

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
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

    @Test("Round-trips across formats", arguments: formatRoundTripCases)
    func formats(testCase: FormatRoundTripCase) throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor(configuration: testCase.compress).compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: testCase.decompress)
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

        try [UInt8]().withSpan { span in
            try decompressor.decompress(span) { _ in
                Issue.record("handler must not be called for an empty chunk")
            }
        }
        do { let finished = decompressor.isFinished; #expect(!finished) }

        try compressed.withSpan { span in
            try decompressor.decompress(span) { chunk in
                output.append(span: chunk)
            }
        }
        #expect(output == input)
        do { let finished = decompressor.isFinished; #expect(finished) }
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
                try [byte].withSpan { span in
                    try decompressor.decompress(span) { _ in }
                }
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
        try truncated.withSpan { span in
            try decompressor.decompress(span) { _ in }
        }
        do { let finished = decompressor.isFinished; #expect(!finished) }
    }

    @Test("One-shot decompress of truncated input throws truncatedInput")
    func truncatedOneShot() throws {
        let input = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor().compress(input)
        let truncated = Array(compressed[..<(compressed.count / 2)])

        #expect(throws: Deflate.Error.truncatedInput) {
            _ = try Deflate.Decompressor().decompress(truncated)
        }
    }

    @Test("Trailing junk after a zlib stream throws unexpectedTrailingData")
    func trailingJunkZlib() throws {
        let input = Array("complete stream".utf8)
        let compressed = try Deflate.Compressor().compress(input) + [0xDE, 0xAD, 0xBE, 0xEF]

        #expect(throws: Deflate.Error.unexpectedTrailingData) {
            _ = try Deflate.Decompressor().decompress(compressed)
        }
    }

    @Test("Trailing junk in a later chunk throws unexpectedTrailingData")
    func trailingJunkLaterChunk() throws {
        let input = Array("complete stream".utf8)
        let compressed = try Deflate.Compressor().compress(input)

        var decompressor = Deflate.StreamingDecompressor(configuration: .default)
        try compressed.withSpan { span in
            try decompressor.decompress(span) { _ in }
        }
        do { let finished = decompressor.isFinished; #expect(finished) }

        #expect(throws: Deflate.Error.unexpectedTrailingData) {
            try [0xDE, 0xAD].withSpan { span in
                try decompressor.decompress(span) { _ in }
            }
        }
    }

    @Test("Trailing junk after a gzip stream throws corruptData")
    func trailingJunkGzip() throws {
        // gzip defaults to concatenated-member support, so trailing bytes are
        // parsed as the next member's header and fail as corrupt.
        let input = Array("complete stream".utf8)
        let compressed =
            try Deflate.Compressor(configuration: .gzip).compress(input) + [0xDE, 0xAD, 0xBE, 0xEF]

        #expect(throws: Deflate.Error.corruptData) {
            _ = try Deflate.Decompressor(configuration: .gzip).decompress(compressed)
        }
    }

    @Test("Concatenated gzip members decompress by default")
    func concatenatedGzipMembers() throws {
        let first = Array("first member, ".utf8)
        let second = Array("second member".utf8)
        let compressor = Deflate.Compressor(configuration: .gzip)
        let compressed = try compressor.compress(first) + compressor.compress(second)

        let output = try Deflate.Decompressor(configuration: .gzip).decompress(compressed)
        #expect(output == first + second)
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
            try [byte].withSpan { span in
                try decompressor.decompress(span) { chunk in
                    output.append(span: chunk)
                }
            }
        }
        #expect(output == first + second)
        do { let finished = decompressor.isFinished; #expect(finished) }
    }

    @Test("Concatenated zlib streams decompress when opted in")
    func concatenatedZlibOptIn() throws {
        let first = Array("first stream, ".utf8)
        let second = Array("second stream".utf8)
        let compressor = Deflate.Compressor()
        let compressed = try compressor.compress(first) + compressor.compress(second)

        let output = try Deflate.Decompressor(
            configuration: .init(allowsConcatenatedStreams: true)
        ).decompress(compressed)
        #expect(output == first + second)
    }
}
