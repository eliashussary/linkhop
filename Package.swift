// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Linkhop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Linkhop", path: "Sources/Linkhop")
    ],
    swiftLanguageModes: [.v5]
)
