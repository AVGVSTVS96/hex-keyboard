import XCTest

final class OneHandedTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOneHanded", "off", "-iikbOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "iikb is not the active keyboard")
    }

    private var field: XCUIElement { app.textViews.firstMatch }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "iikb.\(name)").firstMatch
    }

    private var expander: XCUIElement { app.buttons.matching(identifier: "iikb.expand").firstMatch }

    private func holdNumbersAndPick(atX x: CGFloat) {
        let numbers = key("numbers")
        let pick = numbers.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - numbers.frame.minX, dy: -35))
        numbers.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1, thenDragTo: pick)
    }

    func testHoldingNumbersMovesTheKeysToEitherThumbAndTheArrowBringsThemBack() {
        let fullWidth = key("q").frame.width
        holdNumbersAndPick(atX: 41)
        XCTAssertTrue(expander.waitForExistence(timeout: 2))
        XCTAssertLessThan(key("q").frame.width, fullWidth - 5)
        XCTAssertLessThan(key("p").frame.maxX, app.frame.width - 60)
        XCTAssertTrue(key("numbers").exists, "picking a hand brings the letters back")

        holdNumbersAndPick(atX: 137)
        XCTAssertGreaterThan(key("q").frame.minX, 60)

        for letter in "hi" { key(String(letter)).tap() }
        XCTAssertEqual(field.value as? String, "Hi")

        expander.tap()
        XCTAssertFalse(expander.waitForExistence(timeout: 1))
        XCTAssertEqual(key("q").frame.width, fullWidth, accuracy: 0.5)
    }

    /// Holding the emoji key opens the same menu holding 123 does, as Apple's does on the Duo. `scripts/layoutmenu` shoots it.
    func testHoldingEmojiOpensTheLayoutMenu() throws {
        let emoji = key("emoji")
        XCTAssertTrue(emoji.waitForExistence(timeout: 5), "the emoji key sits beside space")
        let pick = emoji.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: -45))
        if let shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"] {
            FileManager.default.createFile(atPath: shots + ".holding", contents: nil)
            emoji.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1, thenDragTo: pick, withVelocity: .slow, thenHoldForDuration: 10)
        } else {
            emoji.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1, thenDragTo: pick)
        }
        XCTAssertTrue(key("space").waitForExistence(timeout: 2))
    }
}
