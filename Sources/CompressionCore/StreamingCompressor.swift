/// An incremental compressor. Carries LZ77 (or equivalent) context across calls.
///
/// Feed bytes with `compress(_:handler:)` until done, then call `finish(handler:)`
/// to flush the final block.
public protocol StreamingCompressor: ~Copyable, Sendable {
    associatedtype Configuration: CompressionParameters
    associatedtype Failure: Swift.Error = Never

    /// Size of the scratch buffer used by `compress(_:handler:)` and `finish(handler:)`.
    static var outputBufferSize: Int { get }

    var configuration: Configuration { get }

    init(configuration: Configuration)

    /// Compress `chunk` into the provided `OutputSpan`.
    @discardableResult
    mutating func compress(
        _ chunk: Span<UInt8>,
        into output: inout OutputSpan<UInt8>
    ) throws(Failure) -> Int

    /// Flush any remaining compressed data and finalize the stream.
    @discardableResult
    mutating func finish(
        into output: inout OutputSpan<UInt8>
    ) throws(Failure) -> Bool
}

extension StreamingCompressor where Self: ~Copyable {
    public static var outputBufferSize: Int { 32 * 1024 }

    /// Compress `chunk` into the provided `OutputSpan`.
    public mutating func compress(
        _ chunk: Span<UInt8>,
        handler: (Span<UInt8>) throws(Failure) -> Void
    ) throws(Failure) {
        var consumed = 0
        var hasStoppedOnFullOutput: Bool = true
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output throws(Failure) in
            repeat {
                consumed += try compress(chunk.extracting(consumed...), into: &output)
                hasStoppedOnFullOutput = output.isFull
                if !output.isEmpty {
                    try handler(output.span)
                    output.removeAll()
                }
            } while hasStoppedOnFullOutput || consumed < chunk.count
        }
    }

    /// Flush any remaining compressed data and finalize the stream.
    ///
    /// The handler may be called zero or more times.
    public mutating func finish(
        handler: (Span<UInt8>) throws(Failure) -> Void
    ) throws(Failure) {
        var isFinished = false
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output throws(Failure) in
            repeat {
                isFinished = try finish(into: &output)
                if !output.isEmpty {
                    try handler(output.span)
                    output.removeAll()
                }
            } while !isFinished
        }
    }
}
