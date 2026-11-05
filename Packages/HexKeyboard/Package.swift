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
        .target(name: "KeyboardArbiter"),
        .target(name: "KeyboardUI", dependencies: ["KeyboardCore", "KeyboardArbiter"], exclude: ["Resources/LEXICON-LICENSE", "Resources/NETWORK-LICENSE"], resources: [.copy("Resources/en.lexicon"), .copy("Resources/en.network"), .copy("Resources/en.swipe"), .copy("Resources/SWIPE-LICENSE"), .copy("Resources/emoji.txt"), .copy("Resources/emoji-search.txt"), .copy("Resources/Keys")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "MinimalKeyboard", dependencies: ["KeyboardCore", "KeyboardUI"], path: "Examples/MinimalKeyboard"),
        .executableTarget(name: "LexiconBuilder", dependencies: ["KeyboardCore"], path: "Tools/LexiconBuilder"),
        .executableTarget(name: "NetworkBuilder", dependencies: ["KeyboardCore"], path: "Tools/NetworkBuilder"),
        .executableTarget(name: "SwipeBuilder", dependencies: ["KeyboardCore"], path: "Tools/SwipeBuilder"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
        .testTarget(name: "KeyboardUITests", dependencies: ["KeyboardUI"], resources: [.copy("phrases.txt"), .copy("chat.txt"), .copy("klipy.json")]),
    ]
)
