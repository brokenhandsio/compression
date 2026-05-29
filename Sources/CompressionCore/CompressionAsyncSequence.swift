#if canImport(_Concurrency)
import _Concurrency

public struct CompressionAsyncSequence<
    BackingSequence: AsyncSequence,
    Algorithm: StreamingCompressionAlgorithm
>: AsyncSequence where BackingSequence.Element: CompressibleInput {
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

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Error) -> [UInt8]? {
            if let chunk = try await backingIterator.next(isolation: actor) {
                compressor.buffer.removeAll(keepingCapacity: true)
                try chunk.withSpan { inputSpan in
                    try compressor.value.compress(inputSpan) { resultSpan in
                        unsafe compressor.buffer.append(span: resultSpan)
                    }
                }
                return compressor.buffer
            } else if !finished {
                compressor.buffer.removeAll(keepingCapacity: true)
                defer { finished = true }
                try compressor.value.finish { resultSpan in
                    unsafe compressor.buffer.append(span: resultSpan)
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
