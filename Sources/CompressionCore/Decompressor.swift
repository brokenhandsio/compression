/// A stateless, one-shot decompressor.
///
/// Each call decodes a complete compressed payload. For incremental input,
/// see `StreamingDecompressor`.
public protocol Decompressor: Sendable {
    associatedtype Configuration: DecompressionParameters
    associatedtype Failure: Swift.Error
    var configuration: Configuration { get }

    init(configuration: Configuration)

    /// Decompress `input` and return a new buffer sized to the result.
    func decompress(_ input: some CompressibleInput) throws(Failure) -> [UInt8]

    /// Decompress `input` into `output`, advancing its initialized count.
    /// Throws if `output` doesn't have enough free capacity.
    func decompress(_ input: some CompressibleInput, into output: inout OutputSpan<UInt8>) throws(Failure)
}
