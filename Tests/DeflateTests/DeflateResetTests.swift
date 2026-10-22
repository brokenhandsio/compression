import CompressionDeflate
import Testing

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

@Suite("Deflate reset")
struct DeflateResetTests {
    @Test("A stream compressed after reset decodes on its own")
    func streamAfterResetIsSelfContained() throws {
        var compressor = Deflate.StreamingCompressor()
        var firstStream = [UInt8]()
        var secondStream = [UInt8]()

        try compressor.compress(payload.span) { firstStream += bytes($0) }
        try compressor.finish { firstStream += bytes($0) }
        compressor.reset()
        try compressor.compress(payload.span) { secondStream += bytes($0) }
        try compressor.finish { secondStream += bytes($0) }

        let decompressor = Deflate.Decompressor()
        #expect(try decompressor.decompress(firstStream) == payload)
        #expect(try decompressor.decompress(secondStream) == payload)
    }

    @Test("reset discards a stream that was never finished")
    func resetDiscardsUnfinishedStream() throws {
        var compressor = Deflate.StreamingCompressor()
        var discarded = [UInt8]()
        try compressor.compress(payload.span) { discarded += bytes($0) }

        compressor.reset()

        var stream = [UInt8]()
        try compressor.compress(other.span) { stream += bytes($0) }
        try compressor.finish { stream += bytes($0) }

        #expect(try Deflate.Decompressor().decompress(stream) == other)
    }

    @Test("After reset the compressor behaves like a fresh one with the same configuration")
    func resetKeepsConfiguration() throws {
        let configuration = Deflate.CompressionConfiguration(level: .best, format: .gzip)

        var reused = Deflate.StreamingCompressor(configuration: configuration)
        var throwaway = [UInt8]()
        try reused.compress(payload.span) { throwaway += bytes($0) }
        try reused.finish { throwaway += bytes($0) }
        reused.reset()
        var reusedStream = [UInt8]()
        try reused.compress(payload.span) { reusedStream += bytes($0) }
        try reused.finish { reusedStream += bytes($0) }

        var fresh = Deflate.StreamingCompressor(configuration: configuration)
        var freshStream = [UInt8]()
        try fresh.compress(payload.span) { freshStream += bytes($0) }
        try fresh.finish { freshStream += bytes($0) }

        #expect(reusedStream == freshStream, "reset must not drop level, format or memory")
        let decompressor = Deflate.Decompressor(configuration: .init(format: .gzip))
        #expect(try decompressor.decompress(reusedStream) == payload)
    }

    @Test("After reset a second independent stream decodes")
    func resetAllowsASecondStream() throws {
        let stream = try Deflate.Compressor().compress(payload)
        var decompressor = Deflate.StreamingDecompressor()

        var first = [UInt8]()
        try decompressor.decompress(stream.span) { first += bytes($0) }
        // #expect can't read a property off a ~Copyable value, so bind it first.
        let finishedAfterFirst = decompressor.isFinished
        #expect(first == payload)
        #expect(finishedAfterFirst)

        decompressor.reset()
        let finishedAfterReset = decompressor.isFinished
        #expect(!finishedAfterReset)

        var second = [UInt8]()
        try decompressor.decompress(stream.span) { second += bytes($0) }
        let finishedAfterSecond = decompressor.isFinished
        #expect(second == payload)
        #expect(finishedAfterSecond)
    }

    /// Without this, a reused decompressor keeps counting bytes from the stream
    /// before it and trips `maxDecompressedSize` on a stream that is within the limit.
    @Test("reset clears the byte count so maxDecompressedSize applies per stream")
    func resetClearsTheByteCount() throws {
        let stream = try Deflate.Compressor().compress(payload)
        let configuration = Deflate.DecompressionConfiguration(maxDecompressedSize: payload.count)
        var decompressor = Deflate.StreamingDecompressor(configuration: configuration)

        var first = [UInt8]()
        try decompressor.decompress(stream.span) { first += bytes($0) }
        #expect(first == payload)

        decompressor.reset()

        var second = [UInt8]()
        try decompressor.decompress(stream.span) { second += bytes($0) }
        #expect(second == payload)
    }

    @Test("reset discards a partially fed stream")
    func resetDiscardsPartialInput() throws {
        let stream = try Deflate.Compressor().compress(payload)
        var decompressor = Deflate.StreamingDecompressor()

        var partial = [UInt8]()
        try decompressor.decompress(Array(stream.prefix(stream.count / 2)).span) { partial += bytes($0) }
        let finishedAfterPartial = decompressor.isFinished
        #expect(!finishedAfterPartial)

        decompressor.reset()

        var whole = [UInt8]()
        try decompressor.decompress(stream.span) { whole += bytes($0) }
        let finishedAtEnd = decompressor.isFinished
        #expect(whole == payload)
        #expect(finishedAtEnd)
    }
}
