public protocol StreamingDecompressor: ~Copyable, Sendable {
    associatedtype Configuration: CompressionConfiguration
    var configuration: Configuration { get }

    init(configuration: Configuration) throws

    /// Decompress `chunk` and call `handler` with each produced output span.
    ///
    /// The handler may be called zero or more times per invocation, depending
    /// on the compression ratio and internal buffer size.
    mutating func decompress(_ chunk: Span<UInt8>, handler: (Span<UInt8>) throws -> Void) throws
}
