/// An incremental decompressor. Accepts compressed input in arbitrarily-sized chunks.
///
/// No `finish` step: the underlying format signals end-of-stream itself.
public protocol StreamingDecompressor: ~Copyable, Sendable {
    associatedtype Configuration: CompressionParameters
    associatedtype Failure: Swift.Error

    var configuration: Configuration { get }

    /// True once the format's end-of-stream marker has been observed.
    ///
    /// Compression formats are self-terminating, so this is the only way to
    /// distinguish a completely decompressed stream from one whose input was
    /// truncated. Consumers should check this after the last chunk has been
    /// fed and treat `false` as an error.
    var isFinished: Bool { get }

    init(configuration: Configuration)

    /// Decompress `chunk` and call `handler` with each produced output span.
    ///
    /// The handler may be called zero or more times per invocation, depending
    /// on the compression ratio and internal buffer size.
    @discardableResult
    mutating func decompress(
        _ chunk: Span<UInt8>,
        handler: (Span<UInt8>) throws(Failure) -> Void
    ) throws(Failure) -> Int
}
