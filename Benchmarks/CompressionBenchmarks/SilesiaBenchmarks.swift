import Benchmark
import CompressionDeflate

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

private let fixturesPath: String = {
    // Benchmarks/CompressionBenchmarks -> Benchmarks/Fixtures
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CompressionBenchmarks/
        .deletingLastPathComponent()  // Benchmarks/
        .appendingPathComponent("Fixtures")
    return url.path
}()

private func loadFixture(_ name: String) -> [UInt8] {
    let path = "\(fixturesPath)/\(name)"
    guard let data = FileManager.default.contents(atPath: path) else {
        fatalError("Missing fixture '\(name)'. Run: scripts/fetch-silesia.sh")
    }
    return [UInt8](data)
}

private let mozilla = loadFixture("mozilla")
private let dickens = loadFixture("dickens")
private let xray = loadFixture("x-ray")

private let mozillaCompressed = try! Deflate.Compressor().compress(mozilla)
private let dickensCompressed = try! Deflate.Compressor().compress(dickens)
private let xrayCompressed = try! Deflate.Compressor().compress(xray)

func silesiaBenchmarks() {
    Benchmark("Compress/zlib/default/dickens") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor().compress(dickens))
        }
    }

    Benchmark("Compress/zlib/speed/dickens") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .fast).compress(dickens))
        }
    }

    Benchmark("Compress/zlib/best/dickens") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .best).compress(dickens))
        }
    }

    Benchmark("Compress/zlib/default/mozilla") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor().compress(mozilla))
        }
    }

    Benchmark("Compress/zlib/speed/mozilla") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .fast).compress(mozilla))
        }
    }

    Benchmark("Compress/zlib/best/mozilla") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .best).compress(mozilla))
        }
    }

    Benchmark("Compress/zlib/default/x-ray") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor().compress(xray))
        }
    }

    Benchmark("Compress/zlib/speed/x-ray") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .fast).compress(xray))
        }
    }

    Benchmark("Compress/zlib/best/x-ray") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Compressor(configuration: .best).compress(xray))
        }
    }

    Benchmark("Decompress/zlib/dickens") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Decompressor().decompress(dickensCompressed))
        }
    }

    Benchmark("Decompress/zlib/mozilla") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Decompressor().decompress(mozillaCompressed))
        }
    }

    Benchmark("Decompress/zlib/x-ray") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try Deflate.Decompressor().decompress(xrayCompressed))
        }
    }

    for chunkSize in [4_096, 32_768, 262_144] {
        Benchmark("StreamingCompress/zlib/mozilla/\(chunkSize / 1_024)KB-chunks") { benchmark in
            var output = [UInt8]()
            output.reserveCapacity(mozilla.count)
            for _ in benchmark.scaledIterations {
                output.removeAll(keepingCapacity: true)
                var compressor = try Deflate.StreamingCompressor(configuration: .default)
                var offset = 0
                while offset < mozilla.count {
                    let end = min(mozilla.count, offset + chunkSize)
                    try mozilla[offset..<end].withSpan {
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

    for chunkSize in [4_096, 32_768, 262_144] {
        Benchmark("StreamingDecompress/zlib/mozilla/\(chunkSize / 1_024)KB-chunks") { benchmark in
            var output = [UInt8]()
            output.reserveCapacity(mozilla.count)
            for _ in benchmark.scaledIterations {
                output.removeAll(keepingCapacity: true)
                var decompressor = try Deflate.StreamingDecompressor(configuration: .default)
                var offset = 0
                while offset < mozillaCompressed.count {
                    let end = min(mozillaCompressed.count, offset + chunkSize)
                    try mozillaCompressed[offset..<end].withSpan {
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
