// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Puplet",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "Puplet",
            path: "Sources/Puplet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
