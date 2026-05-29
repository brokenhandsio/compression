/// An incremental compressor. Carries LZ77 (or equivalent) context across calls.
///
/// Feed bytes with `compress(_:handler:)` until done, then call `finish(handler:)`
/// to flush the final block.
public protocol StreamingCompressor: ~Copyable, Sendable {
    associatedtype Configuration: CompressionParameters
    associatedtype Failure: Swift.Error

    var configuration: Configuration { get }

    init(configuration: Configuration)

    /// Compress `chunk` and call `handler` with each produced output span.
    ///
    /// The handler may be called zero or more times per invocation, depending
    /// on how much output the compressor produces for the given input.
    mutating func compress(
        _ chunk: Span<UInt8>,
        handler: (Span<UInt8>) throws(Failure) -> Void
    ) throws(Failure)

    /// Flush any remaining compressed data and finalize the stream.
    ///
    /// The handler may be called zero or more times.
    mutating func finish(
        handler: (Span<UInt8>) throws(Failure) -> Void
    ) throws(Failure)
}
