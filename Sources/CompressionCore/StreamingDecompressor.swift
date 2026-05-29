/// An incremental decompressor. Accepts compressed input in arbitrarily-sized chunks.
///
/// No `finish` step: the underlying format signals end-of-stream itself.
public protocol StreamingDecompressor: ~Copyable, Sendable {
    associatedtype Configuration: CompressionParameters
    associatedtype Failure: Swift.Error

    var configuration: Configuration { get }

    init(configuration: Configuration)

    /// Decompress `chunk` and call `handler` with each produced output span.
    ///
    /// The handler may be called zero or more times per invocation, depending
    /// on the compression ratio and internal buffer size.
    mutating func decompress(
        _ chunk: Span<UInt8>,
        handler: (Span<UInt8>) throws(Failure) -> Void
    ) throws(Failure)
}
