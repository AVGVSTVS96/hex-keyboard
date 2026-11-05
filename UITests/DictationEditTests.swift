import XCTest

/// What dictations become, against the stand-in for the app (`scripts/edittest`, which leaves each dictation with a
/// transcript's id and checks what the app kept): a long one edited in the middle, then a short one edited at its end,
/// each sent with return, which empties the field as a messaging app does (`-iikbSends`). The app opens once more at the
/// end, so it takes any edit it hadn't yet.
final class DictationEditTests: XCTestCase {
    private var app: XCUIApplication!
    private var field: XCUIElement { app.textViews.firstMatch }
    private var text: String { field.value as? String ?? "" }

    func testWhatDictationsBecomeIsKeptWithTheirTranscripts() throws {
        guard let ended = ProcessInfo.processInfo.environment["IIKB_ENDED"] else { throw XCTSkip("Run through scripts/edittest") }
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbSends", "YES", "-iikbOrientation", "portrait", "-iikbOneHanded", "off", "-iikbMicKey", "NO"]
        app.launch()
        if !key("space").waitForExistence(timeout: 10) {
            app.terminate()
            app.launch()
        }

        dictate()
        XCTAssertTrue(wait { self.text.count > 600 }, "the long dictation is typed")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        for _ in 0..<6 { key("delete").tap() }
        for letter in "zebra" { key(String(letter)).tap() }
        let long = text
        XCTAssertTrue(long.contains("zebra") && !long.hasSuffix("zebra"), "the edit is inside the dictation: \(long)")
        try long.write(toFile: ended + "/long.ended", atomically: true, encoding: .utf8)
        send()

        dictate()
        XCTAssertTrue(wait { self.text.hasSuffix("soon.") }, "the short dictation is typed: \(self.text)")
        for _ in 0..<5 { key("delete").tap() }
        for letter in "now" { key(String(letter)).tap() }
        try text.write(toFile: ended + "/short.ended", atomically: true, encoding: .utf8)
        send()
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 3)
    }

    private func dictate() {
        let mic = app.buttons["iikb.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "iikb is not the active keyboard")
        XCTAssertTrue(wait { mic.label == "Dictate" })
        mic.tap()
        XCTAssertTrue(wait { mic.label == "Stop Dictating" })
        mic.tap()
    }

    private func send() {
        let sent = text
        key("return").tap()
        XCTAssertTrue(wait { !self.text.contains(sent) }, "return sends, emptying the field: \(self.text)")
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func key(_ name: String) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
