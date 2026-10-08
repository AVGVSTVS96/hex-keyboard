import XCTest

final class TypingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES"]
        app.launch()
        XCTAssertTrue(app.keys["q"].waitForExistence(timeout: 10) || app.keys["Q"].exists, "Hex keyboard is not the active keyboard")
    }

    private var field: XCUIElement { app.textViews.firstMatch }

    private func tap(_ name: String) {
        let key = app.keys[name].exists ? app.keys[name] : app.keys[name.uppercased()]
        key.tap()
    }

    private func type(_ text: String) {
        for character in text {
            tap(character == " " ? "space" : String(character))
        }
    }

    func testTypesSentenceWithAutocapAndDoubleSpacePeriod() {
        type("hello world  next")
        XCTAssertEqual(field.value as? String, "Hello world. Next")
    }

    func testDeleteAndNumbers() {
        type("ab")
        tap("delete")
        tap("numbers")
        tap("4")
        tap("2")
        tap("space")
        type("go")
        XCTAssertEqual(field.value as? String, "A42 go")
    }

    func testCapsLockWithDoubleTap() {
        let shift = app.keys["shift"]
        shift.tap()
        shift.doubleTap()
        type("abc")
        XCTAssertEqual(field.value as? String, "ABC")
    }
}
