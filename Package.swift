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
        .executableTarget(
            name: "AeroControl",
            dependencies: ["Common"],
            path: "Sources/AeroControl",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        ),
        .testTarget(
            name: "AeroControlTests",
            dependencies: ["Common", "AeroControl"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v6), .strictMemorySafety()]
        )
    ]
)
