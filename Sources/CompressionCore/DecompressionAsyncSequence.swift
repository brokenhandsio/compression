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
    let chunkSize: Int

    public init(
        backingSequence: BackingSequence,
        configuration: Algorithm.DecompressionConfiguration,
        chunkSize: Int = 64 * 1024
    ) {
        self.backingSequence = backingSequence
        self.configuration = configuration
        self.chunkSize = chunkSize
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        final class DecompressorBox<D: StreamingDecompressor & ~Copyable> {
            var value: D
            init(_ value: consuming D) { self.value = value }
        }

        public typealias Element = [UInt8]

        var backingIterator: BackingSequence.AsyncIterator
        var decompressor: DecompressorBox<Algorithm.StreamingDecompressor>
        let chunkSize: Int

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> [UInt8]? {
            if self.decompressor.value.isFinished, self.decompressor.value.configuration.trailingDataPolicy == .stop {
                return nil
            }

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

            do {
                let result = try [UInt8](capacity: chunkSize) { output throws(Algorithm.StreamingDecompressor.Failure) in
                    _ = try chunk.withSpan { inputSpan throws(Algorithm.StreamingDecompressor.Failure) in
                        try decompressor.value.decompress(inputSpan, into: &output)
                    }
                }
                return result
            } catch {
                throw .decompressorError(error)
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            backingIterator: backingSequence.makeAsyncIterator(),
            decompressor: .init(.init(configuration: configuration)),
            chunkSize: chunkSize
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
