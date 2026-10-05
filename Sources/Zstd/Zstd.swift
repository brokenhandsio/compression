public import CompressionCore

public enum Zstd: Sendable {}

extension Zstd: CompressionAlgorithm {
    public typealias CompressionConfiguration = ZstdCompressionConfiguration
    public typealias DecompressionConfiguration = ZstdDecompressionConfiguration
}
