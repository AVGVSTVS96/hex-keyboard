import XCTest

extension XCTestCase {
    /// Paste from Other Apps › Allow on the Settings page Hex just opened, without which iOS refuses the keyboard's
    /// clipboard reads.
    func allowPasteFromOtherApps() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10), "Turn On opens Settings")
        let paste = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Paste from Other Apps'")).firstMatch
        var path = ["Paste from Other Apps"]
        if !paste.waitForExistence(timeout: 20) {
            settings.terminate()
            settings.launch()
            path = ["Apps", "iikb"] + path
        }
        for label in path {
            let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            _ = row.waitForExistence(timeout: 20)
            var swipes = 0
            while !(row.exists && row.isHittable) && swipes < 10 {
                settings.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(row.exists, "Settings shows \(label)")
            row.tap()
        }
        let allow = settings.descendants(matching: .any).matching(NSPredicate(format: "label == 'Allow'")).firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()
        settings.terminate()
    }
}
