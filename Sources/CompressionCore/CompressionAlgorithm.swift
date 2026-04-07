public protocol CompressionAlgorithm: Sendable {
    associatedtype Configuration: CompressionConfiguration

    associatedtype Compressor: CompressionCore.Compressor where Compressor.Configuration == Configuration
    associatedtype Decompressor: CompressionCore.Decompressor where Decompressor.Configuration == Configuration

    associatedtype StreamingDecompressor: ~Copyable & CompressionCore.StreamingDecompressor
    where StreamingDecompressor.Configuration == Configuration
    associatedtype StreamingCompressor: ~Copyable & CompressionCore.StreamingCompressor
    where StreamingCompressor.Configuration == Configuration
}
