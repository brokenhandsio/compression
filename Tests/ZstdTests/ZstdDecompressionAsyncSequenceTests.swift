import CompressionCore
import Testing
import Zstandard

@Suite("Zstd Decompression Async Sequence")
struct ZstdDecompressionAsyncSequenceTests {
    @Test("Compress then decompress via async sequences")
    func roundTrip() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)

        let compressedStream = makeStream(for: data, chunkSize: 1024).compressed(using: Zstd.self)
        var compressed = [UInt8]()
        for try await chunk in compressedStream {
            compressed.append(contentsOf: chunk)
        }

        let decompressedStream = makeStream(for: compressed, chunkSize: 1024).decompressed(using: Zstd.self)
        var output = [UInt8]()
        for try await chunk in decompressedStream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)
    }

    /// Incompressible input, so the compressed stream is larger than the source
    /// and neither side can coast on a single long match.
    @Test("Incompressible data round-trips via async sequences")
    func roundTripIncompressible() async throws {
        let data = pseudoRandomBytes(count: 1 << 20)

        let compressedStream = makeStream(for: data, chunkSize: 4_096).compressed(using: Zstd.self)
        var compressed = [UInt8]()
        for try await chunk in compressedStream {
            compressed.append(contentsOf: chunk)
        }

        let decompressedStream = makeStream(for: compressed, chunkSize: 4_096).decompressed(using: Zstd.self)
        var output = [UInt8]()
        for try await chunk in decompressedStream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)
    }

    /// One small input chunk can expand to far more than the iterator's scratch
    /// buffer, and every one of those bytes has to reach the caller.
    @Test("A chunk that expands beyond the iterator's buffer is fully delivered")
    func highlyCompressibleSingleChunk() async throws {
        let data = [UInt8](repeating: 0, count: 1 << 22)  // 4MB of zeros
        let compressed = try Zstd.Compressor().compress(data)

        let stream = makeStream(chunks: [compressed]).decompressed(using: Zstd.self)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output.count == data.count)
        #expect(output == data)
    }

    @Test("Truncated input throws .truncatedStream")
    func truncatedInputThrows() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Zstd.Compressor().compress(data)
        let truncated = Array(compressed[..<(compressed.count / 2)])

        let stream = makeStream(for: truncated, chunkSize: 1024).decompressed(using: Zstd.self)
        await #expect {
            for try await _ in stream {}
        } throws: { error in
            guard
                case .truncatedStream =
                    error as? DecompressionAsyncSequence<AsyncStream<ArraySlice<UInt8>>, Zstd>.Failure
            else {
                return false
            }
            return true
        }
    }

    @Test("Trailing data is not returned when policy is stop")
    func trailingDataIsNotReturned() async throws {
        let data = Array(repeating: UInt8(0x61), count: 50_000)
        let compressed = try Zstd.Compressor().compress(data)
        let trailingData = [UInt8](repeating: 0x00, count: 10_000)

        let configuration = Zstd.DecompressionConfiguration(windowLogMax: 0, trailingDataPolicy: .stop)
        let stream = makeStream(for: compressed + trailingData, chunkSize: 1024)
            .decompressed(using: Zstd.self, configuration: configuration)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output == data)  // doesn't contain trailing data
    }

    @Test("Trailing data throws when policy is reject")
    func rejectTrailingData() async throws {
        let compressed = try Zstd.Compressor().compress(Array("complete stream".utf8))
        // One chunk, so the frame end and the garbage reach the decompressor together.
        let chunk = compressed + [UInt8](repeating: 0xDE, count: 8)

        let configuration = Zstd.DecompressionConfiguration(windowLogMax: 0, trailingDataPolicy: .reject)
        let stream = makeStream(chunks: [chunk])
            .decompressed(using: Zstd.self, configuration: configuration)
        await #expect {
            for try await _ in stream {}
        } throws: { error in
            guard
                case .decompressorError(.unexpectedTrailingData) =
                    error as? DecompressionAsyncSequence<AsyncStream<[UInt8]>, Zstd>.Failure
            else {
                return false
            }
            return true
        }
    }

    @Test("Concatenated frames in separate chunks are all decompressed")
    func concatenatedFramesInSeparateChunks() async throws {
        let first = Array("first frame, ".utf8)
        let second = Array("second frame".utf8)
        let compressor = Zstd.Compressor()

        let stream = makeStream(chunks: [try compressor.compress(first), try compressor.compress(second)])
            .decompressed(using: Zstd.self)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output == first + second)
    }

    @Test("Concatenated frames inside one chunk are all decompressed")
    func concatenatedFramesInOneChunk() async throws {
        let first = Array("first frame, ".utf8)
        let second = Array("second frame".utf8)
        let compressor = Zstd.Compressor()
        let chunk = try compressor.compress(first) + (try compressor.compress(second))

        let stream = makeStream(chunks: [chunk]).decompressed(using: Zstd.self)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output == first + second)
    }

    @Test("An empty source produces an empty stream rather than a frame")
    func emptySourceCompresses() async throws {
        let compressedStream = makeStream(chunks: [[UInt8]()]).compressed(using: Zstd.self)
        var compressed = [UInt8]()
        for try await chunk in compressedStream {
            compressed.append(contentsOf: chunk)
        }

        let stream = makeStream(chunks: [compressed]).decompressed(using: Zstd.self)
        var output = [UInt8]()
        for try await chunk in stream {
            output.append(contentsOf: chunk)
        }

        #expect(output.isEmpty)
    }

    @Test("A partially consumed chunk is resumed even when no input was consumed", arguments: [1, 2, 16, 64])
    func partiallyConsumedChunkIsResumed(chunkSize: Int) async throws {
        let data = [UInt8](repeating: 0x41, count: 256 * 1024)
        let compressed = try Zstd.Compressor().compress(data)

        let stream = DecompressionAsyncSequence<AsyncStream<[UInt8]>, Zstd>(
            backingSequence: makeStream(chunks: split(compressed, every: 64)),
            configuration: .default,
            chunkSize: chunkSize
        )

        var output = [UInt8]()
        var elements = 0
        for try await chunk in stream {
            output.append(contentsOf: chunk)
            elements += 1
            if elements > 4 * (data.count / chunkSize + 1_000) { break }
        }

        #expect(output.count == data.count, "every byte must be delivered")
        #expect(output == data)
    }

    /// Mirror of the above on the compression side: zstd buffers input and then
    /// emits a whole block, so a call can produce a full output buffer without
    /// consuming anything from the chunk it was given.
    @Test("Compression resumes a partially consumed chunk", arguments: [1, 16, 64])
    func compressionResumesPartiallyConsumedChunk(chunkSize: Int) async throws {
        let data = pseudoRandomBytes(count: 128 * 1024)

        let stream = CompressionAsyncSequence<AsyncStream<[UInt8]>, Zstd>(
            backingSequence: makeStream(chunks: split(data, every: 4_096)),
            configuration: .default,
            chunkSize: chunkSize
        )

        var compressed = [UInt8]()
        var elements = 0
        for try await chunk in stream {
            compressed.append(contentsOf: chunk)
            elements += 1
            if elements > 4 * (data.count / chunkSize + 1_000) { break }
        }

        #expect(try Zstd.Decompressor().decompress(compressed) == data)
    }

    private func split(_ bytes: [UInt8], every size: Int) -> [[UInt8]] {
        stride(from: 0, to: bytes.count, by: size).map {
            Array(bytes[$0..<min($0 + size, bytes.count)])
        }
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
