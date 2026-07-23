// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AeroControl",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "Common",
            path: "Sources/Common",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        ),
        .target(
            name: "AeroControlKit",
            dependencies: ["Common"],
            path: "Sources/AeroControlKit",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        ),
        .executableTarget(
            name: "AeroControl",
            dependencies: ["Common", "AeroControlKit"],
            path: "Sources/AeroControlEntry",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        ),
        .executableTarget(
            name: "PerfBench",
            dependencies: ["Common", "AeroControlKit"],
            path: "Benchmarks/PerfBench",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        ),
        .testTarget(
            name: "AeroControlTests",
            dependencies: ["Common", "AeroControlKit"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        )
    ]
)
