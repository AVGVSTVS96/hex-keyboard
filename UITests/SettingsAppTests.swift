import XCTest

final class SettingsAppTests: XCTestCase {
    func testSettingsAppSharesSwitchesWithHex() throws {
        let hex = XCUIApplication()
        hex.launchArguments = ["-HexResetSettings", "YES", "-HexSettings", "keys"]
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
        open("Keys", in: settings)
        let inSettings = settings.switches["Character Preview"]
        XCTAssertTrue(inSettings.waitForExistence(timeout: 5))
        if let path = ProcessInfo.processInfo.environment["HEX_SETTINGS_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        inSettings.switches.firstMatch.tap()
        XCTAssertEqual(inSettings.value as? String, "0")
        settings.terminate()

        hex.launchArguments = ["-HexSettings", "keys"]
        hex.launch()
        XCTAssertTrue(inHex.waitForExistence(timeout: 5))
        XCTAssertEqual(inHex.value as? String, "0")
    }

    func testKeepMicOnIsPickedInHexAndShownInSettings() throws {
        let hex = XCUIApplication()
        hex.launchArguments = ["-HexResetSettings", "YES", "-HexSettings", "voice"]
        hex.launch()
        let picked = hex.buttons["5 Minutes"]
        XCTAssertTrue(hex.navigationBars["Voice Typing"].waitForExistence(timeout: 5))
        for _ in 0 ..< 6 where !picked.isHittable { hex.swipeUp() }
        XCTAssertTrue(picked.isSelected)
        try shot(hex, "keep-mic-on-choices")
        let minute = hex.buttons["1 Minute"]
        while !minute.isHittable { hex.swipeUp() }
        minute.tap()
        XCTAssertTrue(minute.isSelected)
        XCTAssertFalse(picked.isSelected)
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
        open("Voice Typing", in: settings)
        XCTAssertTrue(settings.staticTexts["Keep Mic On"].waitForExistence(timeout: 5))
        XCTAssertTrue(settings.descendants(matching: .any).matching(NSPredicate(format: "label == '1 Minute' OR value == '1 Minute'")).firstMatch.exists)
        try shot(settings, "keep-mic-on-settings")
        settings.terminate()
    }

    /// Opens one of Hex's pages in Settings › Apps › Hex.
    private func open(_ page: String, in settings: XCUIApplication) {
        let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", page)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        while !row.isHittable { settings.swipeUp() }
        row.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["HEX_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}
