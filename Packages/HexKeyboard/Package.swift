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
        .target(name: "KeyboardUI", dependencies: ["KeyboardCore"], exclude: ["Resources/LEXICON-LICENSE"], resources: [.copy("Resources/en.lexicon"), .copy("Resources/en.next")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "LexiconBuilder", dependencies: ["KeyboardCore"], path: "Tools/LexiconBuilder"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
        .testTarget(name: "KeyboardUITests", dependencies: ["KeyboardUI"], resources: [.copy("phrases.txt")]),
    ]
)
