// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrossApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DrossApp",
            resources: [.copy("Resources")]
        )
    ]
)
