import CompressionDeflate
import Testing

@Suite("Deflate Decompression Async Sequence")
struct DeflateDecompressionAsyncSequenceTests {
    @Test("Compress then decompress via async sequences")
    func roundTrip() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)

        let compressedStream = makeStream(for: data, chunkSize: 1024).compressed(using: Deflate.self)
        var compressed = [UInt8]()
        for try await chunk in compressedStream {
            compressed.append(contentsOf: chunk)
        }

        let decompressedStream = makeStream(for: compressed, chunkSize: 1024).decompressed(using: Deflate.self)
        var output = [UInt8]()
        for try await chunk in decompressedStream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)
    }

    @Test("Truncated input throws .truncatedStream")
    func truncatedInputThrows() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor().compress(data)
        let truncated = Array(compressed[..<(compressed.count / 2)])

        let stream = makeStream(for: truncated, chunkSize: 1024).decompressed(using: Deflate.self)
        await #expect {
            for try await _ in stream {}
        } throws: { error in
            guard case .truncatedStream = error as? DecompressionAsyncSequence<AsyncStream<ArraySlice<UInt8>>, Deflate>.Failure else {
                return false
            }
            return true
        }
    }

    @Test("Trailing data is not returned when policy is stop")
    func trailingDataIsNotReturned() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Deflate.Compressor().compress(data)
        let trailingData = Array(repeating: UInt8(0x00), count: 10_000)

        let configuration = Deflate.DecompressionConfiguration(trailingDataPolicy: .stop)
        let stream = makeStream(for: compressed + trailingData, chunkSize: 1024)
            .decompressed(using: Deflate.self, configuration: configuration)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)  // doesn't contain trailing data
    }

    @Test("Stream ending on a chunk boundary stops before the next chunk when policy is stop")
    func stopOnChunkBoundary() async throws {
        let data = Array("complete stream".utf8)
        let compressed = try Deflate.Compressor().compress(data)

        let configuration = Deflate.DecompressionConfiguration(trailingDataPolicy: .stop)
        let stream = makeStream(chunks: [compressed, [0xDE, 0xAD, 0xBE, 0xEF]])
            .decompressed(using: Deflate.self, configuration: configuration)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)
    }

    @Test("Trailing data in a later chunk throws when policy is reject")
    func rejectTrailingDataInLaterChunk() async throws {
        let compressed = try Deflate.Compressor().compress(Array("complete stream".utf8))

        let stream = makeStream(chunks: [compressed, [0xDE, 0xAD, 0xBE, 0xEF]])
            .decompressed(using: Deflate.self)
        await #expect {
            for try await _ in stream {}
        } throws: { error in
            guard
                case .decompressorError(.unexpectedTrailingData) =
                    error as? DecompressionAsyncSequence<AsyncStream<[UInt8]>, Deflate>.Failure
            else {
                return false
            }
            return true
        }
    }

    @Test("Concatenated gzip members in separate chunks are all decompressed")
    func concatenatedGzipMembersInSeparateChunks() async throws {
        let first = Array("first member, ".utf8)
        let second = Array("second member".utf8)
        let compressor = Deflate.Compressor(configuration: .gzip)

        let stream = makeStream(chunks: [try compressor.compress(first), try compressor.compress(second)])
            .decompressed(using: Deflate.self, configuration: .gzip)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output == first + second)
    }

    private func makeStream(chunks: [[UInt8]]) -> AsyncStream<[UInt8]> {
        AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private func makeStream<Body: Collection & Sendable>(
        for message: Body,
        chunkSize: Int = 16
    ) -> AsyncStream<Body.SubSequence>
    where Body.SubSequence: Sendable & CompressibleInput {
        AsyncStream<Body.SubSequence> { continuation in
            var offset = message.startIndex
            while offset < message.endIndex {
                let endIndex = message.index(offset, offsetBy: chunkSize, limitedBy: message.endIndex) ?? message.endIndex
                continuation.yield(message[offset..<endIndex])
                offset = endIndex
            }
            continuation.finish()
        }
    }
}
