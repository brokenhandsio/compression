import Testing
import Zstandard

private let allBoundConfigurations: [ZstdCompressionConfiguration] =
    ([.auto] + allStrategies).map { .init(strategy: $0, level: .default) }
    + [.min, .fastest, .default, .max].map { .init(strategy: .auto, level: $0) }

@Suite("Zstd upperBound")
struct ZstdUpperBoundTests {
    @Test("A buffer of exactly upperBound fits incompressible input", arguments: allBoundConfigurations)
    func boundFitsIncompressibleInput(configuration: ZstdCompressionConfiguration) throws {
        let input = pseudoRandomBytes(count: 128 * 1024)
        let compressor = Zstd.Compressor(configuration: configuration)
        let bound = compressor.upperBound(forInputSize: input.count)

        let compressed = try [UInt8](capacity: bound) { output throws(Zstd.Error) in
            try compressor.compress(input.span, into: &output)
        }

        #expect(try Zstd.Decompressor().decompress(compressed) == input)
        #expect(bound < input.count + 4_096)
    }

    @Test(
        "A buffer of exactly upperBound fits any input size",
        arguments: [0, 1, 2, 3, 100, 1_000, 131_071, 131_072]
    )
    func boundFitsEverySize(size: Int) throws {
        let input = pseudoRandomBytes(count: size)
        let compressor = Zstd.Compressor()
        let bound = compressor.upperBound(forInputSize: size)

        let compressed = try [UInt8](capacity: bound) { output throws(Zstd.Error) in
            try compressor.compress(input.span, into: &output)
        }

        #expect(try Zstd.Decompressor().decompress(compressed) == input)
    }
}
