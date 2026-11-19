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
            name: "CompressionDeflate",
            targets: ["CompressionDeflate"]
        ),
        .library(
            name: "CompressionZstd",
            targets: ["CompressionZstd"]
        ),
        .library(
            name: "CompressionFoundationCompat",
            targets: ["CompressionCore", "CompressionFoundationCompat"]
        ),
    ],
    targets: [
        .target(
            name: "CompressionCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CompressionFoundationCompat",
            dependencies: [
                .target(name: "CompressionCore")
            ],
            swiftSettings: swiftSettings
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
        ),
        .testTarget(
            name: "DeflateTests",
            dependencies: [
                .target(name: "CompressionDeflate")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ZstdTests",
            dependencies: [
                .target(name: "CompressionZstd"),
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
            name: "CompressionZstd",
            dependencies: ["CZstd", "CompressionCore"],
            path: "Sources/Zstd",
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    var settings: [SwiftSetting] = [
        .strictMemorySafety(),
        .interoperabilityMode(.C),
        .enableExperimentalFeature("SafeInteropWrappers"),
        .enableExperimentalFeature("Lifetimes"),
        // https://github.com/swiftlang/swift/issues/88864
        // .enableExperimentalFeature("Embedded"),
        .treatWarning("EmbeddedRestrictions", as: .warning),
    ]
    #if compiler(>=6.4)
    settings.append(.enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"))
    #else
    settings.append(.enableExperimentalFeature("SuppressedAssociatedTypes"))
    #endif
    return settings
}
