public struct DecompressionAsyncSequence<
    BackingSequence: AsyncSequence,
    Algorithm: CompressionAlgorithm
>: AsyncSequence where BackingSequence.Element: CompressibleInput {
    final class DecompressorBox<D: StreamingDecompressor & ~Copyable> {
        var value: D
        var buffer: [UInt8] = []
        init(_ value: consuming D) { self.value = value }
    }

    let backingSequence: BackingSequence
    let decompressor: DecompressorBox<Algorithm.StreamingDecompressor>

    public init(backingSequence: BackingSequence, configuration: Algorithm.Configuration) throws {
        self.backingSequence = backingSequence
        self.decompressor = try .init(.init(configuration: configuration))
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        // No BorrowingAsyncSequence :(
        public typealias Element = [UInt8]

        var backingIterator: BackingSequence.AsyncIterator
        var decompressor: DecompressorBox<Algorithm.StreamingDecompressor>

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Error) -> [UInt8]? {
            guard let chunk = try await backingIterator.next(isolation: actor) else { return nil }
            decompressor.buffer.removeAll(keepingCapacity: true)
            try chunk.withSpan { inputSpan in
                try decompressor.value.decompress(inputSpan) { resultSpan in
                    // TODO: replace with Array(span) when available
                    decompressor.buffer.append(addingCapacity: resultSpan.count) {
                        for i in 0..<resultSpan.count {
                            $0.append(resultSpan[i])
                        }
                    }
                }
            }
            return decompressor.buffer
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(backingIterator: backingSequence.makeAsyncIterator(), decompressor: decompressor)
    }
}

extension AsyncSequence {
    public func decompressed<Algorithm: CompressionAlgorithm>(
        using algorithm: Algorithm.Type,
        configuration: Algorithm.Configuration = .default
    ) throws -> DecompressionAsyncSequence<Self, Algorithm> where Element: CompressibleInput {
        try .init(backingSequence: self, configuration: configuration)
    }
}
