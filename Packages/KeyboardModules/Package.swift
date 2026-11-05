// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KeyboardModules",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
        .library(name: "KeyboardEnglish", targets: ["KeyboardEnglish"]),
        .library(name: "KeyboardStore", targets: ["KeyboardStore"]),
        .library(name: "KeyboardUI", targets: ["KeyboardUI"]),
        .library(name: "FullKeyboard", targets: ["FullKeyboard"]),
    ],
    targets: [
        .target(name: "KeyboardCore", exclude: ["AGENTS.md"]),
        .target(name: "KeyboardArbiter"),
        .target(name: "KeyboardEnglish", dependencies: ["KeyboardCore"], exclude: ["AGENTS.md", "Resources/LEXICON-LICENSE", "Resources/NETWORK-LICENSE"], resources: [.copy("Resources/en.lexicon"), .copy("Resources/en.network"), .copy("Resources/en.swipe"), .copy("Resources/SWIPE-LICENSE"), .copy("Resources/emoji.txt"), .copy("Resources/emoji-search.txt")]),
        .target(name: "KeyboardStore", dependencies: ["KeyboardCore", "KeyboardEnglish"], exclude: ["AGENTS.md"], resources: [.copy("Resources/Keys")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "KeyboardUI", dependencies: ["KeyboardCore", "KeyboardEnglish"], exclude: ["AGENTS.md"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "FullKeyboard", dependencies: ["KeyboardCore", "KeyboardEnglish", "KeyboardStore", "KeyboardUI", "KeyboardArbiter"], exclude: ["AGENTS.md"], resources: [.copy("Resources/Keys")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "MinimalKeyboard", dependencies: ["KeyboardCore", "KeyboardEnglish", "KeyboardUI"], path: "Examples/MinimalKeyboard"),
        .executableTarget(name: "LexiconBuilder", dependencies: ["KeyboardCore"], path: "Tools/LexiconBuilder"),
        .executableTarget(name: "NetworkBuilder", dependencies: ["KeyboardCore"], path: "Tools/NetworkBuilder"),
        .executableTarget(name: "SwipeBuilder", dependencies: ["KeyboardCore"], path: "Tools/SwipeBuilder"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
        .testTarget(name: "KeyboardUITests", dependencies: ["KeyboardEnglish", "KeyboardStore", "KeyboardUI", "FullKeyboard"], resources: [.copy("phrases.txt"), .copy("chat.txt"), .copy("klipy.json")]),
    ]
)
