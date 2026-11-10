/// An incremental decompressor. Accepts compressed input in arbitrarily-sized chunks.
///
/// No `finish` step: the underlying format signals end-of-stream itself.
public protocol StreamingDecompressor: ~Copyable, Sendable {
    associatedtype Configuration: DecompressionParameters
    associatedtype Failure: Swift.Error

    var configuration: Configuration { get }

    /// True once the format's end-of-stream marker has been observed.
    ///
    /// Compression formats are self-terminating, so this is the only way to
    /// distinguish a completely decompressed stream from one whose input was
    /// truncated. Consumers should check this after the last chunk has been
    /// fed and treat `false` as an error.
    var isFinished: Bool { get }

    /// Size of the scratch buffer used by `decompress(_:handler:)`.
    static var outputBufferSize: Int { get }

    init(configuration: Configuration)

    /// Decompress `chunk` into the provided `OutputSpan`.
    @discardableResult
    mutating func decompress(
        _ chunk: Span<UInt8>,
        into output: inout OutputSpan<UInt8>
    ) throws(Failure) -> StreamStep

    /// Discard all stream state and start over, keeping `configuration`.
    ///
    /// Any data compressed after this is independent of what came before, so it
    /// decodes on its own. A stream that was never finished is dropped.
    mutating func reset()
}

extension StreamingDecompressor where Self: ~Copyable {
    public static var outputBufferSize: Int { 32 * 1024 }

    /// Decompress `chunk`, calling a throwing `handler` with each piece of output.
    ///
    /// - Returns: how many bytes of `chunk` were consumed
    @discardableResult
    public mutating func decompress(
        _ chunk: Span<UInt8>,
        handler: (Span<UInt8>) throws -> Void
    ) throws -> Int {
        var consumed = 0
        var status: StreamStep.Status = .awaitingInput
        try withTemporaryAllocation(of: UInt8.self, capacity: Self.outputBufferSize) { output throws in
            repeat {
                let result = try decompress(chunk.extracting(consumed...), into: &output)
                consumed += result.consumed
                status = result.status
                if !output.isEmpty {
                    try handler(output.span)
                    output.removeAll()
                }
            } while status == .outputIsFull
        }
        return consumed
    }

    /// Decompress `chunk` and append the output to `output`.
    ///
    /// If this throws, `output` may hold up to one `outputBufferSize` of bytes
    /// past `maxDecompressedSize`, so discard it.
    ///
    /// - Returns: how many bytes of `chunk` were consumed
    @discardableResult
    package mutating func decompress(
        _ chunk: Span<UInt8>,
        appendingTo output: inout [UInt8]
    ) throws(Failure) -> Int {
        var consumed = 0
        var status: StreamStep.Status = .awaitingInput
        repeat {
            let spare = min(output.capacity - output.count, Self.outputBufferSize)
            try output.append(addingCapacity: spare > 0 ? spare : Self.outputBufferSize) { tail throws(Failure) in
                let result = try decompress(chunk.extracting(consumed...), into: &tail)
                consumed += result.consumed
                status = result.status
            }
        } while status == .outputIsFull
        return consumed
    }
}
