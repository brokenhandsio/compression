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
        let chunkSize: Int

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> [UInt8]? {
            let chunk: BackingSequence.Element?

            do {
                chunk = try await backingIterator.next(isolation: actor)
            } catch {
                throw .backingStreamError(error)
            }

            if let chunk {
                do {
                    return try chunk.withSpan { inputSpan throws(Algorithm.StreamingCompressor.Failure) in
                        try [UInt8](capacity: chunkSize) { output throws(Algorithm.StreamingCompressor.Failure) in
                            try compressor.value.compress(inputSpan, into: &output)
                        }
                    }
                } catch {
                    throw .compressorError(error)
                }

            } else if !finished {
                defer { finished = true }
                do {
                    return try [UInt8](capacity: chunkSize) { output throws(Algorithm.StreamingCompressor.Failure) in
                        try compressor.value.finish(into: &output)
                    }
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
