// swift-tools-version: 6.2
import PackageDescription

// FluidAudio's version is the app's (root Package.swift).
let package = Package(
    name: "VoiceBench",
    platforms: [.macOS(.v26)],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0")],
    targets: [
        .target(name: "KeyboardStore"),
        .executableTarget(name: "VoiceBench", dependencies: ["KeyboardStore", .product(name: "FluidAudio", package: "FluidAudio")]),
    ]
)
