import Benchmark
import CompressionDeflate

private let compressible1KB = [UInt8](repeating: 0x61, count: 1_024)
private let compressible1MB = [UInt8](repeating: 0x61, count: 1_024 * 1_024)

private let incompressible1MB: [UInt8] = {
    var out = [UInt8](repeating: 0, count: 1_024 * 1_024)
    var state: UInt64 = 0x1234_5678_9ABC_DEF0
    for i in out.indices {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        out[i] = UInt8(state >> 56)
    }
    return out
}()

func deflateBenchmarks() {
    Benchmark("Compress/zlib/default/1KB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor().compress(compressible1KB))
        }
    }

    Benchmark("Compress/zlib/default/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor().compress(compressible1MB))
        }
    }

    Benchmark("Compress/zlib/speed/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .fast).compress(compressible1MB))
        }
    }

    Benchmark("Compress/zlib/best/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .best).compress(compressible1MB))
        }
    }

    Benchmark("Compress/raw/default/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .raw).compress(compressible1MB))
        }
    }

    Benchmark("Compress/gzip/default/1MB") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .gzip).compress(compressible1MB))
        }
    }

    Benchmark("Compress/zlib/default/1MB/incompressible") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor().compress(incompressible1MB))
        }
    }

    for chunkSize in [4_096, 32_768, 262_144] {
        Benchmark("StreamingCompress/zlib/1MB/\(chunkSize / 1_024)KB-chunks") { benchmark in
            for _ in benchmark.scaledIterations {
                var compressor = try Deflate.StreamingCompressor(configuration: .default)
                var output = [UInt8]()
                var offset = 0
                while offset < compressible1MB.count {
                    let end = min(compressible1MB.count, offset + chunkSize)
                    try compressible1MB[offset..<end].withSpan {
                        try compressor.compress($0) { chunk in
                            output.append(addingCapacity: chunk.count) {
                                for i in 0..<chunk.count { $0.append(chunk[i]) }
                            }
                        }
                    }
                    offset = end
                }
                try compressor.finish { chunk in
                    output.append(addingCapacity: chunk.count) {
                        for i in 0..<chunk.count { $0.append(chunk[i]) }
                    }
                }
                blackHole(output)
            }
        }
    }
}
