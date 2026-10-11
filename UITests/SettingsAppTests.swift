import XCTest

final class SettingsAppTests: XCTestCase {
    func testSettingsAppSharesSwitchesWithHex() throws {
        let hex = XCUIApplication()
        hex.launchArguments = ["-HexResetSettings", "YES", "-HexSettings", "YES"]
        hex.launch()
        let inHex = hex.switches["Character Preview"]
        XCTAssertTrue(inHex.waitForExistence(timeout: 5))
        XCTAssertEqual(inHex.value as? String, "1")
        hex.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["Hex"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        let inSettings = settings.switches["Character Preview"]
        XCTAssertTrue(inSettings.waitForExistence(timeout: 5))
        if let path = ProcessInfo.processInfo.environment["HEX_SETTINGS_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        inSettings.switches.firstMatch.tap()
        XCTAssertEqual(inSettings.value as? String, "0")
        settings.terminate()

        hex.launchArguments = ["-HexSettings", "YES"]
        hex.launch()
        XCTAssertTrue(inHex.waitForExistence(timeout: 5))
        XCTAssertEqual(inHex.value as? String, "0")
    }
}
