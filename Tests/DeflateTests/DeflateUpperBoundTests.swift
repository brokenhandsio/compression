import CompressionDeflate
import Testing

private let allBoundConfigurations: [Deflate.CompressionConfiguration] =
    [Deflate.Format.zlib, .raw, .gzip].flatMap { format in
        [Deflate.MemoryUsage.custom(1), .low, .default, .high].flatMap { memory in
            [Deflate.Level.none, .speed, .best].map { level in
                Deflate.CompressionConfiguration(level: level, format: format, memory: memory)
            }
        }
    }

@Suite("Deflate upperBound")
struct DeflateUpperBoundTests {
    @Test("A buffer of exactly upperBound fits incompressible input", arguments: allBoundConfigurations)
    func boundFitsIncompressibleInput(configuration: Deflate.CompressionConfiguration) throws {
        let input = pseudoRandomBytes(count: 256 * 1024)
        let compressor = Deflate.Compressor(configuration: configuration)
        let bound = compressor.upperBound(forInputSize: input.count)

        let compressed = try [UInt8](capacity: bound) { output throws(Deflate.Error) in
            try compressor.compress(input.span, into: &output)
        }

        let decompressor = Deflate.Decompressor(configuration: .init(format: configuration.format))
        #expect(try decompressor.decompress(compressed) == input)
        #expect(bound < input.count + input.count / 4 + 1_024)
    }

    @Test(
        "A buffer of exactly upperBound fits any input size",
        arguments: [0, 1, 2, 3, 39, 40, 100, 65_536], [Deflate.Format.raw, .zlib, .gzip])
    func boundFitsEverySize(size: Int, format: Deflate.Format) throws {
        let input = pseudoRandomBytes(count: size)
        let compressor = Deflate.Compressor(configuration: .init(format: format))
        let bound = compressor.upperBound(forInputSize: size)

        let compressed = try [UInt8](capacity: bound) { output throws(Deflate.Error) in
            try compressor.compress(input.span, into: &output)
        }

        #expect(try Deflate.Decompressor(configuration: .init(format: format)).decompress(compressed) == input)
    }
}
