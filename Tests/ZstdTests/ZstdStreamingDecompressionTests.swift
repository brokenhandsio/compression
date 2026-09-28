import Testing
import Zstandard

@Suite("Zstd Streaming Decompression Tests")
struct ZstdStreamingDecompressionTests {
    @Test("Output larger than ZSTD_DStreamOutSize")
    func largeOutput() throws {
        let maxOutputSize = 1 << 24  // 16MB
        let input = [UInt8](repeating: 0, count: maxOutputSize)

        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()
        #expect(throws: Never.self) {
            try decompressor.decompress(compressed.span) { output in
                decompressed.append(span: output)
            }
        }

        #expect(decompressor.isFinished == true)
    }

    @Test("Truncated output leaves isFinished = false and does not throw")
    func truncatedOutput() throws {
        let input = [UInt8](repeating: 0, count: 1 << 10)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()
        let truncated = compressed[..<(compressed.count - 2)]
        try decompressor.decompress(truncated.span) { output in
            decompressed.append(span: output)
        }

        #expect(decompressor.isFinished == false)
    }

    @Test("Feed compressed data one byte at a time")
    func oneByteAtATime() throws {
        let input = Array("streaming one byte at a time".utf8).cycled(times: 64)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()

        for index in compressed.indices {
            try decompressor.decompress(compressed.span.extracting(index..<(index + 1))) { output in
                decompressed.append(span: output)
            }
        }

        #expect(decompressor.isFinished == true)
        #expect(decompressed == input)
    }

    /// Incompressible input, so the decoder has to move real bytes rather than
    /// expanding a single long match.
    @Test("Round-trips across chunk sizes", arguments: [1, 16, 256, 4_096, 32_768, 65_536, 131_073])
    func chunkSizes(chunkSize: Int) throws {
        let input = pseudoRandomBytes(count: 1 << 20)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()

        for start in stride(from: 0, to: compressed.count, by: chunkSize) {
            let end = min(start + chunkSize, compressed.count)
            try decompressor.decompress(compressed.span.extracting(start..<end)) { output in
                decompressed.append(span: output)
            }
        }

        #expect(decompressor.isFinished == true)
        #expect(decompressed == input)
    }

    @Test("Empty chunk is a no-op")
    func emptyChunk() throws {
        let input = Array(repeating: UInt8(0x41), count: 4_096)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var handlerCalls = 0
        var decompressor = Zstd.StreamingDecompressor()

        // Before any real input: nothing produced, still unfinished.
        try decompressor.decompress(Span<UInt8>()) { output in
            handlerCalls += 1
            decompressed.append(span: output)
        }
        #expect(handlerCalls == 0)
        #expect(decompressor.isFinished == false)

        try decompressor.decompress(compressed.span) { output in
            decompressed.append(span: output)
        }
        #expect(decompressor.isFinished == true)

        // After the frame ends an empty chunk must not disturb the state.
        try decompressor.decompress(Span<UInt8>()) { output in
            decompressed.append(span: output)
        }
        #expect(decompressor.isFinished == true)
        #expect(decompressed == input)
    }

    /// `isFinished` reports the state of the stream as of the last chunk, so a
    /// frame that ended must not keep it `true` once a new frame starts.
    @Test("isFinished resets when a new frame begins")
    func isFinishedResets() throws {
        let first = Array("first frame".utf8).cycled(times: 32)
        let second = Array("second frame".utf8).cycled(times: 32)
        let frameA = try Zstd.Compressor().compress(first)
        let frameB = try Zstd.Compressor().compress(second)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()

        try decompressor.decompress(frameA.span) { decompressed.append(span: $0) }
        #expect(decompressor.isFinished == true)

        let split = frameB.count / 2
        try decompressor.decompress(frameB.span.extracting(..<split)) { decompressed.append(span: $0) }
        #expect(decompressor.isFinished == false, "a partial frame must clear the finished flag")

        try decompressor.decompress(frameB.span.extracting(split...)) { decompressed.append(span: $0) }
        #expect(decompressor.isFinished == true)
        #expect(decompressed == first + second)
    }

    @Test("Concatenated frames in one chunk decompress")
    func concatenatedFrames() throws {
        let first = Array("alpha".utf8).cycled(times: 100)
        let second = Array("beta".utf8).cycled(times: 100)
        let compressed = try Zstd.Compressor().compress(first) + Zstd.Compressor().compress(second)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()
        try decompressor.decompress(compressed.span) { decompressed.append(span: $0) }

        #expect(decompressor.isFinished == true)
        #expect(decompressed == first + second)
    }

    @Test("Concatenated frames split across chunks decompress")
    func concatenatedFramesSplit() throws {
        let first = Array("alpha".utf8).cycled(times: 100)
        let second = Array("beta".utf8).cycled(times: 100)
        let frameA = try Zstd.Compressor().compress(first)
        let compressed = frameA + (try Zstd.Compressor().compress(second))

        // Split part-way into the second frame, so one chunk spans the boundary.
        let split = frameA.count + 3

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()
        try decompressor.decompress(compressed.span.extracting(..<split)) { decompressed.append(span: $0) }
        try decompressor.decompress(compressed.span.extracting(split...)) { decompressed.append(span: $0) }

        #expect(decompressor.isFinished == true)
        #expect(decompressed == first + second)
    }

    @Test("Frames without a declared content size decompress")
    func unknownContentSize() throws {
        let input = Array("no pledged size here".utf8).cycled(times: 500)
        let compressed = try streamingCompress(input)
        #expect(frameContentSize(of: compressed) == nil, "streamed frames record no content size")

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor()
        try decompressor.decompress(compressed.span) { decompressed.append(span: $0) }

        #expect(decompressor.isFinished == true)
        #expect(decompressed == input)
    }

    // MARK: - Limits

    @Test("maxDecompressedSize is enforced")
    func maxDecompressedSizeEnforced() throws {
        let input = Array(repeating: UInt8(0x41), count: 100_000)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor(
            configuration: .init(windowLogMax: 0, maxDecompressedSize: 1_000)
        )

        #expect(throws: Zstd.Error.maxDecompressedSizeExceeded) {
            try decompressor.decompress(compressed.span) { decompressed.append(span: $0) }
        }
        #expect(decompressed.count <= 1_000, "the limit must be checked before the handler sees the bytes")
    }

    @Test("maxDecompressedSize accumulates across chunks")
    func maxDecompressedSizeAccumulates() throws {
        let input = Array(repeating: UInt8(0x41), count: 100_000)
        let compressed = try Zstd.Compressor().compress(input)

        // Comfortably above any single chunk's output, well below the total.
        var decompressor = Zstd.StreamingDecompressor(
            configuration: .init(windowLogMax: 0, maxDecompressedSize: 50_000)
        )

        var decompressed = [UInt8]()
        var thrown: Zstd.Error?
        let chunkSize = 16

        for start in stride(from: 0, to: compressed.count, by: chunkSize) {
            let end = min(start + chunkSize, compressed.count)
            do {
                try decompressor.decompress(compressed.span.extracting(start..<end)) {
                    decompressed.append(span: $0)
                }
            } catch {
                thrown = error
                break
            }
        }

        #expect(thrown == .maxDecompressedSizeExceeded)
        #expect(decompressed.count <= 50_000)
    }

    /// `windowLogMax` caps the back-reference window the decoder will allocate
    /// for. A 1 MB frame needs roughly 2^20, so a 2^10 limit must reject it.
    @Test("windowLogMax rejects a frame with a larger window")
    func windowLogMaxRejectsLargeWindow() throws {
        let input = pseudoRandomBytes(count: 1 << 20)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressor = Zstd.StreamingDecompressor(configuration: .init(windowLogMax: 10))

        #expect(throws: Zstd.Error.windowTooLarge) {
            try decompressor.decompress(compressed.span) { _ in }
        }
    }

    @Test("expectedContentSize matching the frame succeeds")
    func expectedContentSizeMatches() throws {
        let input = Array(repeating: UInt8(0x41), count: 10_000)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressed = [UInt8]()
        var decompressor = Zstd.StreamingDecompressor(
            configuration: .init(windowLogMax: 0, expectedContentSize: input.count)
        )
        try decompressor.decompress(compressed.span) { decompressed.append(span: $0) }

        #expect(decompressor.isFinished == true)
        #expect(decompressed == input)
    }

    @Test("expectedContentSize mismatch throws", arguments: [9_999, 10_001])
    func expectedContentSizeMismatch(expected: Int) throws {
        let input = Array(repeating: UInt8(0x41), count: 10_000)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressor = Zstd.StreamingDecompressor(
            configuration: .init(windowLogMax: 0, expectedContentSize: expected)
        )

        #expect(throws: Zstd.Error.contentSizeMismatch(expected: expected, actual: input.count)) {
            try decompressor.decompress(compressed.span) { _ in }
        }
    }

    // MARK: - Failures

    @Test("Garbage input throws")
    func garbageThrows() {
        let garbage: [UInt8] = [0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9, 0xF8]
        var decompressor = Zstd.StreamingDecompressor()

        #expect(throws: Zstd.Error.corruptData) {
            try decompressor.decompress(garbage.span) { _ in }
        }
    }

    @Test("Corrupted payload throws corruptData")
    func corruptedPayloadThrows() throws {
        let input = Array(repeating: UInt8(0x41), count: 4_096)
        var compressed = try Zstd.Compressor().compress(input)
        // Flip bits well past the header so the frame still parses.
        for i in (compressed.count - 4)..<compressed.count { compressed[i] ^= 0xFF }

        var decompressor = Zstd.StreamingDecompressor()

        #expect(throws: Zstd.Error.corruptData) {
            try decompressor.decompress(compressed.span) { _ in }
        }
    }

    /// The handler's error is the caller's, and must surface unchanged rather
    /// than being swallowed or replaced by a zstd code.
    @Test("An error thrown by the handler propagates")
    func handlerErrorPropagates() throws {
        let input = Array(repeating: UInt8(0x41), count: 100_000)
        let compressed = try Zstd.Compressor().compress(input)

        var decompressor = Zstd.StreamingDecompressor()

        #expect(throws: Zstd.Error.insufficientMemory) {
            try decompressor.decompress(compressed.span) { _ throws(Zstd.Error) in
                throw Zstd.Error.insufficientMemory
            }
        }
    }
}

// MARK: - Helpers

/// Deterministic pseudo-random bytes, so a failure reproduces exactly.
private func pseudoRandomBytes(count: Int, seed: UInt64 = 0x5DEE_CE66_D000_0001) -> [UInt8] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 33)
    }
}

/// Compress through the streaming compressor, which pledges no content size.
private func streamingCompress(_ input: [UInt8], chunkSize: Int = 16 * 1_024) throws -> [UInt8] {
    var compressor = Zstd.StreamingCompressor()
    var output = [UInt8]()

    for start in stride(from: 0, to: input.count, by: chunkSize) {
        let end = min(start + chunkSize, input.count)
        try compressor.compress(input.span.extracting(start..<end)) { output.append(span: $0) }
    }
    try compressor.finish { output.append(span: $0) }

    return output
}
