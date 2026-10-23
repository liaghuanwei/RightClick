// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RightClick",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RightClick",
            path: "Sources/RightClick"
        )
    ]
)
