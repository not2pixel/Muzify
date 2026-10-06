// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Muzify",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Muzify", path: "Sources/Muzify")
    ]
)
