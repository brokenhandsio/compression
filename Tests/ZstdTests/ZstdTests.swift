import CZstd
import Testing

@testable import Zstandard

@Suite("One-shot Zstd")
struct ZstdTests {
    let compressor = Zstd.Compressor(configuration: .default)
    let decompressor = Zstd.Decompressor(configuration: .default)

    @Test("Empty input round-trips")
    func emptyInput() throws {
        let compressed = try compressor.compress([UInt8]())
        #expect(!compressed.isEmpty, "even empty input produces a frame header")
        #expect(try decompressor.decompress(compressed) == [])
    }

    @Test("Single byte round-trips")
    func singleByte() throws {
        let input: [UInt8] = [0x42]
        #expect(try decompressor.decompress(compressor.compress(input)) == input)
    }

    @Test("Output begins with the zstd magic number")
    func magicNumber() throws {
        let compressed = try compressor.compress(Array("magic".utf8))
        #expect(Array(compressed.prefix(4)) == zstdMagicNumber)
    }

    @Test("Frame header records the content size")
    func recordsContentSize() throws {
        let input = Array(repeating: UInt8(0x5A), count: 4_096)
        let compressed = try compressor.compress(input)
        #expect(frameContentSize(of: compressed) == input.count)
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

    @Test("Text round-trips")
    func text() throws {
        let input = Array("Hello, world! Hello, world! Hello, world!".utf8)
        #expect(try decompressor.decompress(compressor.compress(input)) == input)
    }

    @Test("Round-trips across every strategy", arguments: allStrategies)
    func roundTripStrategies(strategy: ZstdCompressionConfiguration.Strategy) throws {
        let input = Array(
            "The quick brown fox jumps over the lazy dog. ".utf8
        ).cycled(times: 200)

        let c = Zstd.Compressor(configuration: .init(strategy: strategy, level: 5))
        #expect(try decompressor.decompress(c.compress(input)) == input)
    }

    @Test("Round-trips across compression levels", arguments: [1, 3, 5, 9, 12, 19, 22])
    func roundTripLevels(level: Int32) throws {
        let input = Array("Level \(level) payload. ".utf8).cycled(times: 500)

        let c = Zstd.Compressor(configuration: .init(strategy: .greedy, level: .init(rawValue: level)))
        #expect(try decompressor.decompress(c.compress(input)) == input)
    }

    @Test("Higher levels compress no worse than level 1")
    func higherLevelsCompressBetter() throws {
        let input = Array("Repetitive content that should compress well. ".utf8)
            .cycled(times: 1_000)

        let low = try Zstd.Compressor(configuration: .init(strategy: .greedy, level: 1))
            .compress(input)
        let high = try Zstd.Compressor(configuration: .init(strategy: .btultra, level: 19))
            .compress(input)

        #expect(high.count <= low.count)
        #expect(try decompressor.decompress(low) == input)
        #expect(try decompressor.decompress(high) == input)
    }

    @Test("Compresses from ArraySlice")
    func compressesArraySlice() throws {
        let input = Array("Slice test!".utf8)
        let padded: [UInt8] = [0, 0, 0] + input + [0, 0, 0]
        let slice = padded[3..<(3 + input.count)]

        #expect(try decompressor.decompress(compressor.compress(slice)) == input)
    }

    @Test("Decompresses from ArraySlice")
    func decompressesArraySlice() throws {
        let input = Array("Slice decompress!".utf8)
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

        let compressed = try [UInt8](capacity: bound) { output throws(Zstd.Error) in
            try compressor.compress(input.span, into: &output)
        }

        #expect(!compressed.isEmpty)
        #expect(compressed.count <= bound)
        #expect(try decompressor.decompress(compressed) == input)
    }

    @Test("compress(_:into:) throws outputBufferTooSmall when capacity is too small")
    func compressIntoOutputSpanOverflow() throws {
        // Pseudo-random input so it doesn't compress well. 4 bytes is below the
        // smallest possible zstd frame header.
        var rng = SystemRandomNumberGenerator()
        let input = (0..<4_096).map { _ in UInt8.random(in: 0...255, using: &rng) }

        #expect(throws: Zstd.Error.outputBufferTooSmall) {
            _ = try [UInt8](capacity: 4) { output throws(Zstd.Error) in
                try compressor.compress(input.span, into: &output)
            }
        }
    }

    @Test("decompress(_:into:) round-trips into a caller-supplied buffer")
    func decompressIntoOutputSpan() throws {
        let input = Array(repeating: UInt8(0x41), count: 10_000)
        let compressed = try compressor.compress(input)

        let decompressed = try [UInt8](capacity: input.count) { output throws(Zstd.Error) in
            try decompressor.decompress(compressed.span, into: &output)
        }

        #expect(decompressed == input)
    }

    @Test("decompress(_:into:) throws outputBufferTooSmall when capacity is too small")
    func decompressIntoOutputSpanOverflow() throws {
        let input = Array(repeating: UInt8(0x41), count: 10_000)
        let compressed = try compressor.compress(input)

        #expect(throws: Zstd.Error.outputBufferTooSmall) {
            _ = try [UInt8](capacity: 64) { output throws(Zstd.Error) in
                try decompressor.decompress(compressed.span, into: &output)
            }
        }
    }

    /// `compress(_:into:)` must append at the span's tail rather than overwrite
    /// from the head, and must leave previously written bytes intact.
    @Test("compress(_:into:) appends after existing content")
    func compressIntoOutputSpanAppends() throws {
        let prefix: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let input = Array("appended payload".utf8)

        let combined = try [UInt8](capacity: prefix.count + input.count + 64) { output throws(Zstd.Error) in
            for byte in prefix { output.append(byte) }
            try compressor.compress(input.span, into: &output)
        }

        #expect(Array(combined.prefix(4)) == prefix, "existing bytes must survive")
        #expect(combined.count > prefix.count, "compressed bytes must be appended")

        let frame = Array(combined.dropFirst(prefix.count))
        #expect(Array(frame.prefix(4)) == zstdMagicNumber)
        #expect(try decompressor.decompress(frame) == input)
    }

    /// Same contract on the decompression side.
    @Test("decompress(_:into:) appends after existing content")
    func decompressIntoOutputSpanAppends() throws {
        let prefix: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let input = Array("appended plaintext".utf8)
        let compressed = try compressor.compress(input)

        let combined = try [UInt8](capacity: prefix.count + input.count) { output throws(Zstd.Error) in
            for byte in prefix { output.append(byte) }
            try decompressor.decompress(compressed.span, into: &output)
        }

        #expect(combined == prefix + input)
    }

    // MARK: - Decompression failures

    @Test("Garbage input throws")
    func garbageThrows() {
        let garbage: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC, 0xFB]
        #expect(throws: Zstd.Error.self) {
            try decompressor.decompress(garbage)
        }
    }

    @Test("Truncated frame throws truncatedInput")
    func truncatedFrameThrows() throws {
        let input = Array(repeating: UInt8(0x41), count: 4_096)
        let compressed = try compressor.compress(input)
        let truncated = Array(compressed.dropLast(compressed.count / 2))

        #expect(throws: Zstd.Error.truncatedInput) {
            try decompressor.decompress(truncated)
        }
    }

    @Test("Corrupted payload throws corruptData")
    func corruptedPayloadThrows() throws {
        let input = Array(repeating: UInt8(0x41), count: 4_096)
        var compressed = try compressor.compress(input)
        // Flip bits well past the header so the frame still parses.
        for i in (compressed.count - 4)..<compressed.count { compressed[i] ^= 0xFF }

        #expect(throws: Zstd.Error.corruptData) {
            try decompressor.decompress(compressed)
        }
    }

    @Test(
        "Round-trips across a range of sizes",
        arguments: [0, 1, 2, 15, 16, 17, 255, 256, 1_023, 1_024, 65_535, 65_536, 100_000]
    )
    func roundTripSizes(size: Int) throws {
        var rng = SystemRandomNumberGenerator()
        // Semi-compressible: random bytes drawn from a small alphabet.
        let input = (0..<size).map { _ in UInt8.random(in: 65...75, using: &rng) }

        let compressed = try compressor.compress(input)
        #expect(frameContentSize(of: compressed) == size)
        #expect(try decompressor.decompress(compressed) == input)
    }
}

extension Array {
    func cycled(times: Int) -> [Element] {
        var result = [Element]()
        result.reserveCapacity(count * times)
        for _ in 0..<times { result.append(contentsOf: self) }
        return result
    }
}
