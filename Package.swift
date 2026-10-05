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
