import XCTest

final class CaptureTests: XCTestCase {
    func testHoldKeysForScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HEX_CAPTURE"] != nil)
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        let g = key("g", in: app)
        XCTAssertTrue(g.waitForExistence(timeout: 10))
        g.press(forDuration: 4)
        key("e", in: app).press(forDuration: 6)
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
