// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HexKeyboard",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
        .library(name: "KeyboardEnglish", targets: ["KeyboardEnglish"]),
        .library(name: "HexStore", targets: ["HexStore"]),
        .library(name: "KeyboardUI", targets: ["KeyboardUI"]),
    ],
    targets: [
        .target(name: "KeyboardCore"),
        .target(name: "KeyboardArbiter"),
        .target(name: "KeyboardEnglish", dependencies: ["KeyboardCore"], exclude: ["Resources/LEXICON-LICENSE", "Resources/NETWORK-LICENSE"], resources: [.copy("Resources/en.lexicon"), .copy("Resources/en.network"), .copy("Resources/en.swipe"), .copy("Resources/SWIPE-LICENSE"), .copy("Resources/emoji.txt"), .copy("Resources/emoji-search.txt")]),
        .target(name: "HexStore", dependencies: ["KeyboardCore", "KeyboardEnglish"], resources: [.copy("Resources/Keys")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "KeyboardUI", dependencies: ["KeyboardCore", "KeyboardEnglish", "HexStore", "KeyboardArbiter"], resources: [.copy("Resources/Keys")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "MinimalKeyboard", dependencies: ["KeyboardCore", "KeyboardEnglish", "KeyboardUI"], path: "Examples/MinimalKeyboard"),
        .executableTarget(name: "LexiconBuilder", dependencies: ["KeyboardCore"], path: "Tools/LexiconBuilder"),
        .executableTarget(name: "NetworkBuilder", dependencies: ["KeyboardCore"], path: "Tools/NetworkBuilder"),
        .executableTarget(name: "SwipeBuilder", dependencies: ["KeyboardCore"], path: "Tools/SwipeBuilder"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
        .testTarget(name: "KeyboardUITests", dependencies: ["KeyboardEnglish", "HexStore", "KeyboardUI"], resources: [.copy("phrases.txt"), .copy("chat.txt"), .copy("klipy.json")]),
    ]
)
