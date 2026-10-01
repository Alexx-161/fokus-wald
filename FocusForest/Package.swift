// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusForest",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(name: "FocusForest", path: "Sources/FocusForest")
    ]
)
