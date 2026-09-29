/// Algorithm-specific tuning. Each algorithm defines its own configuration types.
public protocol CompressionParameters: Sendable {
    /// Sensible defaults for general use.
    static var `default`: Self { get }
}

public protocol DecompressionParameters: CompressionParameters {
    /// Maximum amount of data we allow to be decompressed.
    /// This protects against decompression bombs.
    var maxDecompressedSize: Int? { get set }

    /// Declares what to do when bytes are encountered after the end of stream.
    var trailingDataPolicy: TrailingDataPolicy { get set }
}

/// Declares what to do when bytes are encountered after the end of stream.
public enum TrailingDataPolicy: Sendable {
    /// Throw `.unexpectedTrailingData`.
    case reject
    /// Ignore them and return consumed input count.
    case stop
    /// We're expecting another member, keep decompressing.
    /// Algorithms without multi-stream support treat this as `.reject`.r
    case concatenate
}
