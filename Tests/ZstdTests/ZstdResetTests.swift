import Testing
import Zstandard

/// 4 KB of repetitive text. Both payloads are identical so that, if `reset()`
/// left the previous frame's match history in place, the second frame would be
/// encoded against it and stop being self-contained.
private let payload: [UInt8] = {
    var bytes = [UInt8]()
    while bytes.count < 4_096 { bytes += Array("the quick brown fox jumps over the lazy dog, ".utf8) }
    return Array(bytes.prefix(4_096))
}()

private let other: [UInt8] = Array(repeating: 0x5A, count: 2_048)

private func bytes(_ span: Span<UInt8>) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(span.count)
    for i in span.indices { out.append(span[i]) }
    return out
}

@Suite("Zstd reset")
struct ZstdResetTests {
    @Test("A frame compressed after reset decodes on its own")
    func frameAfterResetIsSelfContained() throws {
        var compressor = Zstd.StreamingCompressor()
        var firstFrame = [UInt8](), secondFrame = [UInt8]()

        try compressor.compress(payload.span) { firstFrame += bytes($0) }
        try compressor.finish { firstFrame += bytes($0) }
        compressor.reset()
        try compressor.compress(payload.span) { secondFrame += bytes($0) }
        try compressor.finish { secondFrame += bytes($0) }

        let decompressor = Zstd.Decompressor()
        #expect(try decompressor.decompress(firstFrame) == payload)
        #expect(try decompressor.decompress(secondFrame) == payload)
    }

    @Test("reset discards a frame that was never finished")
    func resetDiscardsUnfinishedFrame() throws {
        var compressor = Zstd.StreamingCompressor()
        var discarded = [UInt8]()
        try compressor.compress(payload.span) { discarded += bytes($0) }

        compressor.reset()

        var frame = [UInt8]()
        try compressor.compress(other.span) { frame += bytes($0) }
        try compressor.finish { frame += bytes($0) }

        #expect(try Zstd.Decompressor().decompress(frame) == other)
    }

    @Test("After reset the compressor behaves like a fresh one with the same configuration")
    func resetKeepsConfiguration() throws {
        let configuration = ZstdCompressionConfiguration(strategy: .btopt, level: 9)

        var reused = Zstd.StreamingCompressor(configuration: configuration)
        var throwaway = [UInt8]()
        try reused.compress(payload.span) { throwaway += bytes($0) }
        try reused.finish { throwaway += bytes($0) }
        reused.reset()
        var reusedFrame = [UInt8]()
        try reused.compress(payload.span) { reusedFrame += bytes($0) }
        try reused.finish { reusedFrame += bytes($0) }

        var fresh = Zstd.StreamingCompressor(configuration: configuration)
        var freshFrame = [UInt8]()
        try fresh.compress(payload.span) { freshFrame += bytes($0) }
        try fresh.finish { freshFrame += bytes($0) }

        #expect(reusedFrame == freshFrame, "reset must not drop strategy or level")
        #expect(try Zstd.Decompressor().decompress(reusedFrame) == payload)
    }

    @Test("After reset a second independent stream decodes")
    func resetAllowsASecondStream() throws {
        let frame = try Zstd.Compressor().compress(payload)
        var decompressor = Zstd.StreamingDecompressor()

        var first = [UInt8]()
        try decompressor.decompress(frame.span) { first += bytes($0) }
        // #expect can't read a property off a ~Copyable value, so bind it first.
        let finishedAfterFirst = decompressor.isFinished
        #expect(first == payload)
        #expect(finishedAfterFirst)

        decompressor.reset()
        let finishedAfterReset = decompressor.isFinished
        #expect(!finishedAfterReset)

        var second = [UInt8]()
        try decompressor.decompress(frame.span) { second += bytes($0) }
        let finishedAfterSecond = decompressor.isFinished
        #expect(second == payload)
        #expect(finishedAfterSecond)
    }

    /// Without this, a reused decompressor keeps counting bytes from the stream
    /// before it and trips `maxDecompressedSize` on a stream that is within the limit.
    @Test("reset clears the byte count so maxDecompressedSize applies per stream")
    func resetClearsTheByteCount() throws {
        let frame = try Zstd.Compressor().compress(payload)
        let configuration = Zstd.DecompressionConfiguration(
            windowLogMax: 0,
            maxDecompressedSize: payload.count
        )
        var decompressor = Zstd.StreamingDecompressor(configuration: configuration)

        var first = [UInt8]()
        try decompressor.decompress(frame.span) { first += bytes($0) }
        #expect(first == payload)

        decompressor.reset()

        var second = [UInt8]()
        try decompressor.decompress(frame.span) { second += bytes($0) }
        #expect(second == payload)
    }

    @Test("reset discards a partially fed stream")
    func resetDiscardsPartialInput() throws {
        let frame = try Zstd.Compressor().compress(payload)
        var decompressor = Zstd.StreamingDecompressor()

        var partial = [UInt8]()
        try decompressor.decompress(Array(frame.prefix(frame.count / 2)).span) { partial += bytes($0) }
        let finishedAfterPartial = decompressor.isFinished
        #expect(!finishedAfterPartial)

        decompressor.reset()

        var whole = [UInt8]()
        try decompressor.decompress(frame.span) { whole += bytes($0) }
        let finishedAtEnd = decompressor.isFinished
        #expect(whole == payload)
        #expect(finishedAtEnd)
    }
}
