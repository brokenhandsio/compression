import Benchmark
import CompressionDeflate

private let compressible1KB = [UInt8](repeating: 0x61, count: 1_024)
private let compressible1MB = [UInt8](repeating: 0x61, count: 1_024 * 1_024)

private let zlibCompressed1KB = try! Deflate.Compressor().compress(compressible1KB)
private let zlibCompressed1MB = try! Deflate.Compressor().compress(compressible1MB)
private let rawCompressed1MB = try! Deflate.Compressor(configuration: .raw).compress(compressible1MB)

func inflateBenchmarks() {
    Benchmark("Decompress/zlib/1KB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Decompressor().decompress(zlibCompressed1KB))
        }
    }

    Benchmark("Decompress/zlib/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Decompressor().decompress(zlibCompressed1MB))
        }
    }

    Benchmark("Decompress/raw/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Decompressor(configuration: .raw).decompress(rawCompressed1MB))
        }
    }

    // Measures full lifecycle including StreamingDecompressor init per iteration.
    for chunkSize in [4_096, 32_768, 262_144] {
        Benchmark("StreamingDecompress/zlib/1MB/\(chunkSize / 1_024)KB-chunks") { benchmark in
            for _ in benchmark.scaledIterations {
                var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
                var output = [UInt8]()
                output.reserveCapacity(compressible1MB.count)
                var offset = 0
                while offset < zlibCompressed1MB.count {
                    let end = min(zlibCompressed1MB.count, offset + chunkSize)
                    try zlibCompressed1MB[offset..<end].withSpan {
                        try decompressor.decompress($0) { chunk in
                            output.append(addingCapacity: chunk.count) {
                                for i in 0..<chunk.count { $0.append(chunk[i]) }
                            }
                        }
                    }
                    offset = end
                }
                blackHole(output)
            }
        }
    }
}
