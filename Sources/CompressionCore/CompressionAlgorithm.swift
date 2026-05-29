/// A namespace for a compression format and its codecs.
///
/// Capabilities are declared by also conforming to `OneShotCompressionAlgorithm`,
/// `OneShotDecompressionAlgorithm`, `StreamingCompressionAlgorithm`, and/or
/// `StreamingDecompressionAlgorithm`.
public protocol CompressionAlgorithm: Sendable {
    associatedtype CompressionConfiguration: CompressionParameters
    associatedtype DecompressionConfiguration: CompressionParameters
}

/// Algorithm-specific tuning. Each algorithm defines its own configuration types.
public protocol CompressionParameters: Sendable {
    /// Sensible defaults for general use.
    static var `default`: Self { get }
}

/// An algorithm that supports buffer-to-buffer compression.
public protocol OneShotCompressionAlgorithm: CompressionAlgorithm {
    associatedtype Compressor: CompressionCore.Compressor where Compressor.Configuration == CompressionConfiguration
}

/// An algorithm that supports buffer-to-buffer decompression.
public protocol OneShotDecompressionAlgorithm: CompressionAlgorithm {
    associatedtype Decompressor: CompressionCore.Decompressor where Decompressor.Configuration == DecompressionConfiguration
}

/// An algorithm that supports incremental, chunked compression.
public protocol StreamingCompressionAlgorithm: CompressionAlgorithm {
    associatedtype StreamingCompressor: ~Copyable & CompressionCore.StreamingCompressor
    where StreamingCompressor.Configuration == CompressionConfiguration
}

/// An algorithm that supports incremental, chunked decompression.
public protocol StreamingDecompressionAlgorithm: CompressionAlgorithm {
    associatedtype StreamingDecompressor: ~Copyable & CompressionCore.StreamingDecompressor
    where StreamingDecompressor.Configuration == DecompressionConfiguration
}
