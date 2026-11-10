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

    /// Flush any remaining compressed data.
    @discardableResult
    mutating func flush(
        into output: inout OutputSpan<UInt8>
    ) throws(Failure) -> Bool

    /// Flush any remaining compressed data and finalize the stream.
    @discardableResult
    mutating func finish(
        into output: inout OutputSpan<UInt8>
    ) throws(Failure) -> Bool

    /// Discard all stream state and start over, keeping `configuration`.
    ///
    /// Any data compressed after this is independent of what came before, so it
    /// decodes on its own. A stream that was never finished is dropped.
    mutating func reset()
}

extension StreamingCompressor where Self: ~Copyable {
    public static var outputBufferSize: Int { 32 * 1024 }

    /// Compress `chunk` and call `handler` with the compressed result.
    ///
    /// If the `handler` throws, the stream can't continue.
    /// Call `reset()` before using it again.
    public mutating func compress(
        _ chunk: Span<UInt8>,
        handler: (Span<UInt8>) throws -> Void
    ) throws {
        var consumed = 0
        var hasStoppedOnFullOutput: Bool = true
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output in
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

    /// Emit all pending compressed data without ending the stream.
    ///
    /// If the `handler` throws, the stream can't continue.
    /// Call `reset()` before using it again.
    public mutating func flush(
        handler: (Span<UInt8>) throws -> Void
    ) throws {
        var isFlushed = false
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output in
            repeat {
                isFlushed = try flush(into: &output)
                if !output.isEmpty {
                    try handler(output.span)
                    output.removeAll()
                }
            } while !isFlushed
        }
    }

    /// Flush any remaining compressed data and finalize the stream.
    ///
    /// If the `handler` throws, the stream can't continue.
    /// Call `reset()` before using it again.
    public mutating func finish(
        handler: (Span<UInt8>) throws -> Void
    ) throws {
        var isFinished = false
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output in
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
