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
        let compressed = try compressor.compress(input)
        #expect(compressed.count < 1_000)
        #expect(try decompressor.decompress(compressed) == input)
    }

    @Test("Incompressible data round-trips")
    func incompressibleData() throws {
        var rng = SystemRandomNumberGenerator()
        let input = (0..<65_536).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let compressed = try compressor.compress(input)
        #expect(compressed.count < input.count + 100)
        #expect(try decompressor.decompress(compressed) == input)
    }

    @Test("Round-trips across formats", arguments: formatRoundTripCases)
    func roundTripFormats(testCase: FormatRoundTripCase) throws {
        let input = Array("Hello, world! Hello, world! Hello, world!".utf8)
        let c = Deflate.Compressor(configuration: testCase.compress)
        let d = Deflate.Decompressor(configuration: testCase.decompress)
        #expect(try d.decompress(c.compress(input)) == input)
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

    // MARK: - OutputSpan one-shot

    @Test("compress(_:into:) round-trips into a caller-supplied buffer")
    func compressIntoOutputSpan() throws {
        let input = Array("OutputSpan compress path".utf8)
        let bound = input.count + 64  // generously above compressBound

        let compressed = try [UInt8](capacity: bound) { output throws(Deflate.Error) in
            try compressor.compress(input.span, into: &output)
        }

        #expect(compressed.count > 0)
        #expect(compressed.count <= bound)
        #expect(try decompressor.decompress(compressed) == input)
    }

    @Test("compress(_:into:) throws outputBufferTooSmall when capacity is too small")
    func compressIntoOutputSpanOverflow() throws {
        // Pseudo-random input so it doesn't compress well. Capacity of 4 bytes
        // is below the smallest possible zlib header + minimal payload.
        var rng = SystemRandomNumberGenerator()
        let input = (0..<4_096).map { _ in UInt8.random(in: 0...255, using: &rng) }

        #expect(throws: Deflate.Error.outputBufferTooSmall) {
            _ = try [UInt8](capacity: 4) { output throws(Deflate.Error) in
                try compressor.compress(input.span, into: &output)
            }
        }
    }

    @Test("decompress(_:into:) round-trips into a caller-supplied buffer")
    func decompressIntoOutputSpan() throws {
        let input = Array(repeating: UInt8(0x41), count: 10_000)
        let compressed = try compressor.compress(input)

        let decompressed = try [UInt8](capacity: input.count) { output throws(Deflate.Error) in
            try decompressor.decompress(compressed.span, into: &output)
        }

        #expect(decompressed == input)
    }

    @Test("decompress(_:into:) throws outputBufferTooSmall when capacity is too small")
    func decompressIntoOutputSpanOverflow() throws {
        let input = Array(repeating: UInt8(0x41), count: 10_000)
        let compressed = try compressor.compress(input)

        #expect(throws: Deflate.Error.outputBufferTooSmall) {
            _ = try [UInt8](capacity: 64) { output throws(Deflate.Error) in
                try decompressor.decompress(compressed.span, into: &output)
            }
        }
    }

    // MARK: - Array-returning convenience

    /// The array convenience must grow past `decompressedSizeHint`. A small hint
    /// is just a starting capacity, not a cap — this is the case that was broken
    /// when the convenience was layered over the fixed-capacity OutputSpan path.
    @Test("Array decompress grows past the size hint")
    func decompressGrowsPastHint() throws {
        let input = [UInt8](repeating: 0, count: 1_000_000)
        let compressed = try compressor.compress(input)

        let d = Deflate.Decompressor(
            configuration: .init(decompressedSizeHint: 1_024)
        )
        let output = try d.decompress(compressed)
        #expect(output == input)
    }

    @Test("Array decompress grows past the hint with no hint at all")
    func decompressGrowsWithoutHint() throws {
        // Compresses to ~1 KB, decompresses to 1 MB. The default heuristic
        // `input.count * 4` is well below the real output size; the convenience
        // must still produce the full result.
        let input = [UInt8](repeating: 0, count: 1_000_000)
        let compressed = try compressor.compress(input)
        #expect(try decompressor.decompress(compressed) == input)
    }

    // MARK: - maxDecompressedSize

    @Test("maxDecompressedSize is enforced by the array convenience")
    func maxDecompressedSizeEnforced() throws {
        let input = [UInt8](repeating: 0, count: 100_000)
        let compressed = try compressor.compress(input)

        let d = Deflate.Decompressor(
            configuration: .init(maxDecompressedSize: 1_024)
        )
        #expect(throws: Deflate.Error.maxDecompressedSizeExceeded) {
            _ = try d.decompress(compressed)
        }
    }

    @Test("maxDecompressedSize equal to actual size succeeds")
    func maxDecompressedSizeBoundary() throws {
        let input = [UInt8](repeating: 0, count: 4_096)
        let compressed = try compressor.compress(input)

        let d = Deflate.Decompressor(
            configuration: .init(maxDecompressedSize: input.count)
        )
        #expect(try d.decompress(compressed) == input)
    }
}

extension Deflate.Error: Equatable {
    public static func == (lhs: Deflate.Error, rhs: Deflate.Error) -> Bool {
        switch (lhs, rhs) {
        case (.insufficientMemory, .insufficientMemory): true
        case (.corruptData, .corruptData): true
        case (.outputBufferTooSmall, .outputBufferTooSmall): true
        case (.maxDecompressedSizeExceeded, .maxDecompressedSizeExceeded): true
        case (.internalError, .internalError): true
        case (.zlib(code: let lhsCode, message: let lhsMessage), .zlib(code: let rhsCode, message: let rhsMessage)):
            lhsCode == rhsCode && lhsMessage == rhsMessage
        default: false
        }
    }
}
