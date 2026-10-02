// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "compression",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Compression",
            targets: ["CompressionCore", "CompressionDeflate", "CompressionFoundation"]
        ),
        .library(
            name: "CompressionDeflate",
            targets: ["CompressionDeflate"]
        ),
        .library(
            name: "CompressionZstd",
            targets: ["Zstandard"]
        ),
    ],
    targets: [
        .target(
            name: "CompressionCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CompressionFoundation",
            dependencies: [
                .target(name: "CompressionCore")
            ]
        ),
        .target(
            name: "CompressionDeflate",
            dependencies: ["CZlib", "CompressionCore"],
            path: "Sources/Zlib",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CZlib",
            path: "Sources/CZlib",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("ENABLE_C_BOUNDS_SAFETY"),
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "DeflateTests",
            dependencies: [
                .target(name: "CompressionDeflate")
            ],
        ),
        .testTarget(
            name: "ZstdTests",
            dependencies: [
                .target(name: "Zstandard"),
                .target(name: "CZstd"),
            ],
        ),
        .target(
            name: "CZstd",
            path: "Sources/CZstd",
            sources: ["lib"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("lib"),
                .define("ENABLE_C_BOUNDS_SAFETY"),
            ],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "Zstandard",
            dependencies: ["CZstd", "CompressionCore"],
            path: "Sources/Zstd",
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .strictMemorySafety(),
        .interoperabilityMode(.C),
        .enableExperimentalFeature("SafeInteropWrappers"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
        .enableExperimentalFeature("Lifetimes"),
        // https://github.com/swiftlang/swift/issues/88864
        // .enableExperimentalFeature("Embedded"),
        .treatWarning("EmbeddedRestrictions", as: .warning),
    ]
}
