/// A stateless, one-shot compressor.
///
/// Each call compresses `input` in isolation; no LZ77 context is carried between calls.
/// For streaming use, see `StreamingCompressor`.
public protocol Compressor: Sendable {
    associatedtype Configuration: CompressionParameters
    associatedtype Failure: Swift.Error

    var configuration: Configuration { get }

    init(configuration: Configuration)

    /// Compress `input` and return a new buffer sized to the result.
    func compress(_ input: some CompressibleInput) throws(Failure) -> [UInt8]

    /// Compress `input` into `output`, advancing its initialized count.
    /// Throws if `output` doesn't have enough free capacity.
    func compress(_ input: some CompressibleInput, into output: inout OutputSpan<UInt8>) throws(Failure)
}
