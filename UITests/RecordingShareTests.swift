import XCTest

/// A transcript's recording sent on, from its menu in the list and from its page: run by scripts/sharetest, which puts
/// a transcript and its sound in the app first, and screenshots each step to IIKB_SHOTS.
final class RecordingShareTests: XCTestCase {
    func testARecordingIsSentFromTheListAndFromItsPage() throws {
        guard let shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"] else { throw XCTSkip("Run through scripts/sharetest") }
        func shot(_ name: String) throws {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)-\(name).png"))
        }
        let iikb = XCUIApplication()
        iikb.launchArguments = ["-iikbTab", "transcripts"]
        iikb.launch()
        let row = iikb.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Hey, running ten minutes late'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        row.press(forDuration: 1.2)
        let send = iikb.buttons["Send in Messages"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(iikb.buttons["Share Recording"].exists)
        try shot("menu")
        iikb.buttons["Share Recording"].tap()
        XCTAssertTrue(sheet(in: iikb).waitForExistence(timeout: 10))
        sleep(2)
        try shot("share-sheet")
        close(iikb)

        row.tap()
        let page = iikb.buttons["Send in Messages"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertTrue(iikb.buttons["Share Recording"].exists)
        try shot("page")
        page.tap()
        sleep(3)
        try shot("send-in-messages")
    }

    private func sheet(in app: XCUIApplication) -> XCUIElement {
        app.otherElements["ActivityListView"].firstMatch
    }

    private func close(_ app: XCUIApplication) {
        let button = app.buttons["Close"].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() } else { app.swipeDown(velocity: .fast) }
        sleep(1)
    }
}
