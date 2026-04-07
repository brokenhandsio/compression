public protocol Compressor: Sendable {
    associatedtype Configuration: CompressionConfiguration
    var configuration: Configuration { get }

    init(configuration: Configuration)

    func compress(_ input: some CompressibleInput) throws -> [UInt8]
}
