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

    public init(
        backingSequence: BackingSequence,
        configuration: Algorithm.CompressionConfiguration
    ) {
        self.backingSequence = backingSequence
        self.configuration = configuration
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = [UInt8]

        final class CompressorBox<C: StreamingCompressor & ~Copyable> {
            var value: C
            var buffer: [UInt8] = []
            init(value: consuming C) { self.value = value }
        }

        var backingIterator: BackingSequence.AsyncIterator
        var compressor: CompressorBox<Algorithm.StreamingCompressor>
        var finished = false

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> [UInt8]? {
            let chunk: BackingSequence.Element?

            do {
                chunk = try await backingIterator.next(isolation: actor)
            } catch {
                throw .backingStreamError(error)
            }

            if let chunk {
                compressor.buffer.removeAll(keepingCapacity: true)
                do {
                    try chunk.withSpan { inputSpan throws(Algorithm.StreamingCompressor.Failure) in
                        try compressor.value.compress(inputSpan) { resultSpan in
                            unsafe compressor.buffer.append(span: resultSpan)
                        }
                    }
                } catch {
                    throw .compressorError(error)
                }
                return compressor.buffer
            } else if !finished {
                compressor.buffer.removeAll(keepingCapacity: true)
                defer { finished = true }
                do {
                    try compressor.value.finish { resultSpan throws(Algorithm.StreamingCompressor.Failure) in
                        unsafe compressor.buffer.append(span: resultSpan)
                    }
                } catch {
                    throw .compressorError(error)
                }
                return compressor.buffer
            }
            return nil
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            backingIterator: backingSequence.makeAsyncIterator(),
            compressor: .init(value: .init(configuration: configuration))
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
