// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HexKeyboard",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
        .library(name: "KeyboardUI", targets: ["KeyboardUI"]),
    ],
    targets: [
        .target(name: "KeyboardCore"),
        .target(name: "KeyboardUI", dependencies: ["KeyboardCore"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ]
)
