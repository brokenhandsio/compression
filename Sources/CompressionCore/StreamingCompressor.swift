public protocol StreamingCompressor: ~Copyable, Sendable {
    associatedtype Configuration: CompressionConfiguration
    var configuration: Configuration { get }

    init(configuration: Configuration) throws

    /// Compress `chunk` and call `handler` with each produced output span.
    ///
    /// The handler may be called zero or more times per invocation, depending
    /// on how much output the compressor produces for the given input.
    mutating func compress(_ chunk: Span<UInt8>, handler: (Span<UInt8>) throws -> Void) throws

    /// Flush any remaining compressed data and finalize the stream.
    ///
    /// The handler may be called zero or more times.
    mutating func finish(handler: (Span<UInt8>) throws -> Void) throws
}
