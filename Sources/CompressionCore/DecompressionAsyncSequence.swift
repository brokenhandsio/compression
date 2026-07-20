#if canImport(_Concurrency)
import _Concurrency

public struct DecompressionAsyncSequence<
    BackingSequence: AsyncSequence,
    Algorithm: StreamingDecompressionAlgorithm
>: AsyncSequence where BackingSequence.Element: CompressibleInput {
    public enum Failure: Error {
        case decompressorError(Algorithm.StreamingDecompressor.Failure)
        /// Input ended before the format's end-of-stream marker was observed.
        case truncatedStream
        case backingStreamError(BackingSequence.Failure)
    }

    let backingSequence: BackingSequence
    let configuration: Algorithm.DecompressionConfiguration

    public init(
        backingSequence: BackingSequence,
        configuration: Algorithm.DecompressionConfiguration
    ) {
        self.backingSequence = backingSequence
        self.configuration = configuration
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        final class DecompressorBox<D: StreamingDecompressor & ~Copyable> {
            var value: D
            var buffer: [UInt8] = []
            init(_ value: consuming D) { self.value = value }
        }

        public typealias Element = [UInt8]

        var backingIterator: BackingSequence.AsyncIterator
        var decompressor: DecompressorBox<Algorithm.StreamingDecompressor>

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> [UInt8]? {
            let chunk: BackingSequence.Element?
            do {
                chunk = try await backingIterator.next(isolation: actor)
            } catch {
                throw .backingStreamError(error)
            }

            guard let chunk else {
                // There's no more input data: the stream must have reached its
                // end-of-stream marker, otherwise the data was truncated.
                guard decompressor.value.isFinished else { throw .truncatedStream }
                return nil
            }

            decompressor.buffer.removeAll(keepingCapacity: true)
            do {
                try chunk.withSpan { inputSpan throws(Algorithm.StreamingDecompressor.Failure) in
                    try decompressor.value.decompress(inputSpan) { resultSpan in
                        unsafe decompressor.buffer.append(span: resultSpan)
                    }
                }
            } catch {
                throw .decompressorError(error)
            }
            return decompressor.buffer
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            backingIterator: backingSequence.makeAsyncIterator(),
            decompressor: .init(.init(configuration: configuration))
        )
    }
}

extension AsyncSequence {
    public func decompressed<Algorithm: CompressionAlgorithm>(
        using algorithm: Algorithm.Type,
        configuration: Algorithm.DecompressionConfiguration = .default
    ) -> DecompressionAsyncSequence<Self, Algorithm>
    where Element: CompressibleInput {
        .init(backingSequence: self, configuration: configuration)
    }
}
#endif
