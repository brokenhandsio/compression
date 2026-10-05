#if canImport(_Concurrency)
import _Concurrency

public struct CompressionAsyncSequence<
    BackingSequence: AsyncSequence,
    Algorithm: StreamingCompressionAlgorithm
>: AsyncSequence where BackingSequence.Element: CompressibleInput {
    public enum Failure: Error {
        case compressorError(Algorithm.StreamingCompressor.Failure)
        case backingStreamError(BackingSequence.Failure)
    }

    let backingSequence: BackingSequence
    let configuration: Algorithm.CompressionConfiguration
    let chunkSize: Int

    public init(
        backingSequence: BackingSequence,
        configuration: Algorithm.CompressionConfiguration,
        chunkSize: Int = 64 * 1024
    ) {
        self.backingSequence = backingSequence
        self.configuration = configuration
        self.chunkSize = chunkSize
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = [UInt8]

        final class CompressorBox<C: StreamingCompressor & ~Copyable> {
            var value: C
            init(value: consuming C) { self.value = value }
        }

        var backingIterator: BackingSequence.AsyncIterator
        var compressor: CompressorBox<Algorithm.StreamingCompressor>
        var finished = false
        var consumed = 0
        let chunkSize: Int
        var chunk: BackingSequence.Element?

        mutating func consume(chunk: BackingSequence.Element) throws(Failure) -> [UInt8] {
            do {
                return try chunk.withSpan { input throws(Algorithm.StreamingCompressor.Failure) in
                    try [UInt8](capacity: chunkSize) { output throws(Algorithm.StreamingCompressor.Failure) in
                        consumed += try compressor.value.compress(input.extracting(consumed...), into: &output)

                        if input.count != consumed {
                            self.chunk = chunk
                        } else {
                            self.chunk = nil
                            self.consumed = 0
                        }
                    }
                }
            } catch {
                throw .compressorError(error)
            }
        }

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> [UInt8]? {
            if let chunk = self.chunk {
                // We consumed part of the last chunk but not all of it, keep consuming that one
                return try consume(chunk: chunk)
            }

            do {
                self.chunk = try await backingIterator.next(isolation: actor)
            } catch {
                throw .backingStreamError(error)
            }

            if let chunk {
                return try consume(chunk: chunk)
            } else if !finished {
                do {
                    let result = try [UInt8](capacity: chunkSize) { output throws(Algorithm.StreamingCompressor.Failure) in
                        finished = try compressor.value.finish(into: &output)
                    }
                    return result
                } catch {
                    throw .compressorError(error)
                }
            }
            return nil
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            backingIterator: backingSequence.makeAsyncIterator(),
            compressor: .init(value: .init(configuration: configuration)),
            chunkSize: chunkSize
        )
    }
}

extension AsyncSequence where Element: CompressibleInput {
    public func compressed<Algorithm: CompressionAlgorithm>(
        using algorithm: Algorithm.Type,
        configuration: Algorithm.CompressionConfiguration = .default
    ) -> CompressionAsyncSequence<Self, Algorithm> {
        .init(backingSequence: self, configuration: configuration)
    }
}
#endif
