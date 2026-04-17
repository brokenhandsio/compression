// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "CompressionBenchmarks",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.4.0")),
    ],
    targets: [
        .executableTarget(
            name: "CompressionBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "Compression", package: "compression"),
            ],
            path: "CompressionBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
