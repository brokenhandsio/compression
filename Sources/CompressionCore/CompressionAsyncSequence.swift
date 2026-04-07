public struct CompressionAsyncSequence<
    BackingSequence: AsyncSequence,
    Algorithm: CompressionAlgorithm
>: AsyncSequence where BackingSequence.Element: CompressibleInput {
    final class CompressorBox<C: StreamingCompressor & ~Copyable> {
        var value: C
        var buffer: [UInt8] = []
        init(value: consuming C) { self.value = value }
    }

    let backingSequence: BackingSequence
    let compressor: CompressorBox<Algorithm.StreamingCompressor>

    public init(backingSequence: BackingSequence, configuration: Algorithm.Configuration) throws {
        self.backingSequence = backingSequence
        self.compressor = try .init(value: .init(configuration: configuration))
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = [UInt8]

        var backingIterator: BackingSequence.AsyncIterator
        var compressor: CompressorBox<Algorithm.StreamingCompressor>
        var finished = false

        public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Error) -> [UInt8]? {
            if let chunk = try await backingIterator.next(isolation: actor) {
                compressor.buffer.removeAll(keepingCapacity: true)
                try chunk.withSpan { inputSpan in
                    try compressor.value.compress(inputSpan) { resultSpan in
                        // TODO: replace with Array(span) when available
                        compressor.buffer.append(addingCapacity: resultSpan.count) {
                            for i in 0..<resultSpan.count {
                                $0.append(resultSpan[i])
                            }
                        }
                    }
                }
                return compressor.buffer
            } else if !finished {
                compressor.buffer.removeAll(keepingCapacity: true)
                defer { finished = true }
                try compressor.value.finish { resultSpan in
                    // TODO: replace with Array(span) when available
                    compressor.buffer.append(addingCapacity: resultSpan.count) {
                        for i in 0..<resultSpan.count {
                            $0.append(resultSpan[i])
                        }
                    }
                }
                return compressor.buffer
            }
            return nil
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(backingIterator: backingSequence.makeAsyncIterator(), compressor: compressor)
    }
}

extension AsyncSequence where Element: CompressibleInput {
    public func compressed<Algorithm: CompressionAlgorithm>(
        using algorithm: Algorithm.Type,
        configuration: Algorithm.Configuration = .default
    ) throws -> CompressionAsyncSequence<Self, Algorithm> {
        try .init(backingSequence: self, configuration: configuration)
    }
}
