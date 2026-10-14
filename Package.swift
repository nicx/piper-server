// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Piper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Piper",
            path: "Sources/Piper"
        )
    ],
    swiftLanguageModes: [.v5]
)
