// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "iikb",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "iikb", targets: ["iikb"]),
        .library(name: "Keyboard", targets: ["Keyboard"]),
    ],
    dependencies: [
        .package(path: "Packages/KeyboardModules"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.0", traits: []),
    ],
    targets: [
        .target(
            name: "iikb",
            dependencies: [
                .product(name: "KeyboardEnglish", package: "KeyboardModules"),
                .product(name: "KeyboardStore", package: "KeyboardModules"),
                .product(name: "KeyboardUI", package: "KeyboardModules"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "App",
            exclude: ["AGENTS.md", "Voice/AGENTS.md", "Assets.xcassets", "Settings.bundle", "iikb.entitlements", "PrivacyInfo.xcprivacy"],
            swiftSettings: settings
        ),
        .target(
            name: "Keyboard",
            dependencies: [.product(name: "FullKeyboard", package: "KeyboardModules")],
            path: "Keyboard",
            exclude: ["Keyboard.entitlements", "PrivacyInfo.xcprivacy"],
            swiftSettings: settings,
            // The principal class is only named in Info.plist, so without -ObjC the linker strips it out of the appex.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
    ]
)
