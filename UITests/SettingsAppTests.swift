import XCTest

final class SettingsAppTests: XCTestCase {
    func testSettingsAppSharesSwitchesWithApp() throws {
        let iikb = XCUIApplication()
        iikb.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "appearance"]
        iikb.launch()
        let inApp = iikb.switches["Emoji Key"]
        XCTAssertTrue(inApp.waitForExistence(timeout: 5))
        XCTAssertEqual(inApp.value as? String, "1")
        iikb.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["iikb"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        open("Layout", in: settings)
        let inSettings = settings.switches["Emoji Key"]
        XCTAssertTrue(inSettings.waitForExistence(timeout: 5))
        if let path = ProcessInfo.processInfo.environment["IIKB_SETTINGS_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        inSettings.switches.firstMatch.tap()
        XCTAssertEqual(inSettings.value as? String, "0")
        settings.terminate()

        iikb.launchArguments = ["-iikbSettings", "appearance"]
        iikb.launch()
        XCTAssertTrue(inApp.waitForExistence(timeout: 5))
        XCTAssertEqual(inApp.value as? String, "0")
    }

    func testKeepMicOnIsPickedInAppAndShownInSettings() throws {
        let iikb = XCUIApplication()
        iikb.launchArguments = ["-iikbResetSettings", "YES", "-iikbSettings", "mic"]
        iikb.launch()
        let picked = iikb.buttons["5 Minutes"]
        XCTAssertTrue(picked.waitForExistence(timeout: 5))
        for _ in 0 ..< 6 where !picked.isHittable { iikb.swipeUp() }
        XCTAssertTrue(picked.isSelected)
        try shot(iikb, "keep-mic-on-choices")
        let minute = iikb.buttons["1 Minute"]
        while !minute.isHittable { iikb.swipeUp() }
        minute.tap()
        XCTAssertTrue(minute.isSelected)
        XCTAssertFalse(picked.isSelected)
        iikb.terminate()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let back = settings.buttons.matching(identifier: "BackButton").firstMatch
        while back.waitForExistence(timeout: 2) { back.tap() }
        let apps = settings.buttons["Apps"].firstMatch
        while !apps.isHittable { settings.swipeUp() }
        apps.tap()
        let entry = settings.buttons["iikb"].firstMatch
        while !entry.isHittable { settings.swipeUp() }
        entry.tap()
        open("Voice Typing", in: settings)
        XCTAssertTrue(settings.staticTexts["Keep Mic On"].waitForExistence(timeout: 5))
        XCTAssertTrue(settings.descendants(matching: .any).matching(NSPredicate(format: "label == '1 Minute' OR value == '1 Minute'")).firstMatch.exists)
        try shot(settings, "keep-mic-on-settings")
        settings.terminate()
    }

    /// Opens one of iikb's pages in Settings › Apps › iikb.
    private func open(_ page: String, in settings: XCUIApplication) {
        let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", page)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        while !row.isHittable { settings.swipeUp() }
        row.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }
}
