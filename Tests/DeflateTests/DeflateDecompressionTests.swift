import CompressionDeflate
import Testing

@Suite("Deflate Decompression")
struct DeflateDecompressionTests {
    @Test("Concatenated zlib streams decompress when opted in")
    func concatenatedZlibOptIn() throws {
        let first = Array("first stream, ".utf8)
        let second = Array("second stream".utf8)
        let compressor = Deflate.Compressor()
        let compressed = try compressor.compress(first) + compressor.compress(second)

        let output = try Deflate.Decompressor(
            configuration: .init(trailingDataPolicy: .concatenate)
        ).decompress(compressed)
        print(String(decoding: output, as: UTF8.self))
        #expect(output == first + second)
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
}
