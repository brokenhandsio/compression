import CompressionCore

/// RFC 1950 zlib, RFC 1951 raw deflate, and RFC 1952 gzip, backed by libz.
public enum Deflate:
    CompressionAlgorithm,
    OneShotCompressionAlgorithm,
    OneShotDecompressionAlgorithm,
    StreamingCompressionAlgorithm,
    StreamingDecompressionAlgorithm
{}
