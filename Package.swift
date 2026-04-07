// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "compression",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "Compression",
            targets: ["CompressionCore", "CompressionDeflate", "CompressionFoundation"]
        )
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
            name: "CompressionTests",
            dependencies: [.target(name: "CompressionDeflate")],
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .strictMemorySafety(),
        .interoperabilityMode(.C),
        .enableExperimentalFeature("SafeInteropWrappers"),
        .unsafeFlags(["-Xcc", "-fexperimental-bounds-safety-attributes"]),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    ]
}
