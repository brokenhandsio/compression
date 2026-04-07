public protocol Decompressor: Sendable {
    associatedtype Configuration: CompressionConfiguration
    var configuration: Configuration { get }

    init(configuration: Configuration)

    func decompress(_ input: some CompressibleInput) throws -> [UInt8]
}
