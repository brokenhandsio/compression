import CompressionDeflate
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

@Suite("One-shot Deflate")
struct DeflateTests {
    let compressor = Deflate.Compressor()
    let decompressor = Deflate.Decompressor()

    @Test("Empty input round-trips")
    func emptyInput() throws {
        let compressed = try compressor.compress([UInt8]())
        #expect(try decompressor.decompress(compressed) == [])
    }

    @Test("Single byte round-trips")
    func singleByte() throws {
        let input: [UInt8] = [0x42]
        #expect(try decompressor.decompress(compressor.compress(input)) == input)
    }

    @Test("Highly compressible data achieves good ratio")
    func highlyCompressibleData() throws {
        let input = [UInt8](repeating: 0, count: 1_000_000)
        let compressed = try compressor.compress(input.span)
        #expect(compressed.count < 1_000)
        #expect(try decompressor.decompress(compressed.span) == input)
    }

    @Test("Incompressible data round-trips")
    func incompressibleData() throws {
        var rng = SystemRandomNumberGenerator()
        let input = (0..<65_536).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let compressed = try compressor.compress(input.span)
        #expect(compressed.count < input.count + 100)
        #expect(try decompressor.decompress(compressed.span) == input)
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
    func roundTripFormats(config: Deflate.Configuration) throws {
        let input = Array("Hello, world! Hello, world! Hello, world!".utf8)
        let c = Deflate.Compressor(configuration: config)
        let d = Deflate.Decompressor(configuration: config)
        #expect(try d.decompress(c.compress(input.span)) == input)
    }

    @Test("Corrupt data throws corruptData error")
    func corruptDataThrows() throws {
        let garbage: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC, 0xFB]
        #expect(throws: Deflate.Error.corruptData) {
            try Deflate.Decompressor().decompress(garbage)
        }
    }

    @Test("Decompresses from ArraySlice")
    func decompressesArraySlice() throws {
        let input = Array("Slice test!".utf8)
        let compressed = try compressor.compress(input)
        let padded: [UInt8] = [0, 0, 0] + compressed + [0, 0, 0]
        let slice = padded[3..<(3 + compressed.count)]
        #expect(try decompressor.decompress(slice) == input)
    }
}

extension Deflate.Error: Equatable {
    public static func == (lhs: Deflate.Error, rhs: Deflate.Error) -> Bool {
        switch (lhs, rhs) {
        case (.insufficientMemory, .insufficientMemory): true
        case (.corruptData, .corruptData): true
        case (.bufferOverflow, .bufferOverflow): true
        case (.internalError, .internalError): true
        case (.zlib(code: let lhsCode, message: let lhsMessage), .zlib(code: let rhsCode, message: let rhsMessage)):
            lhsCode == rhsCode && lhsMessage == rhsMessage
        default: false
        }
    }
}
