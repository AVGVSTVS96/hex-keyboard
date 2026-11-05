// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KeyboardWeb",
    dependencies: [
        .package(path: "../Packages/KeyboardModules"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.59.0"),
    ],
    targets: [
        .executableTarget(
            name: "KeyboardWeb",
            dependencies: [
                .product(name: "KeyboardCore", package: "KeyboardModules"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            swiftSettings: [.enableExperimentalFeature("Extern")],
            plugins: [.plugin(name: "BridgeJS", package: "JavaScriptKit")]
        ),
    ]
)
