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
}
