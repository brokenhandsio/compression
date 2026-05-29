#if canImport(_Concurrency)
import _Concurrency

public struct DecompressionAsyncSequence<
    BackingSequence: AsyncSequence,
    Algorithm: StreamingDecompressionAlgorithm
>: AsyncSequence where BackingSequence.Element: CompressibleInput {
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

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Error) -> [UInt8]? {
            guard let chunk = try await backingIterator.next(isolation: actor) else { return nil }
            decompressor.buffer.removeAll(keepingCapacity: true)
            try chunk.withSpan { inputSpan in
                try decompressor.value.decompress(inputSpan) { resultSpan in
                    unsafe decompressor.buffer.append(span: resultSpan)
                }
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
