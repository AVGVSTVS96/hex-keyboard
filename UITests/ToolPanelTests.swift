import UniformTypeIdentifiers
import XCTest

/// The GIF, clipboard and Transcripts panels and the clipboard's tray through the real keyboard, with Full Access on (scripts/paneltest turns it on). With
/// IIKB_SHOTS set, screenshots each step.
final class ToolPanelTests: XCTestCase {
    private var shots: String?

    override func setUpWithError() throws {
        shots = ProcessInfo.processInfo.environment["IIKB_SHOTS"]
        continueAfterFailure = false
    }

    func testTheGifPanelSearchesKlipyAndCopiesWhatYouTap() throws {
        let app = launch()
        let tool = app.buttons["iikb.tool.gif"]
        XCTAssertTrue(tool.waitForExistence(timeout: 3), "the GIF tool shows when a KLIPY key is built in")
        tool.tap()
        let gifs = app.scrollViews["iikb.gifs"]
        XCTAssertTrue(gifs.waitForExistence(timeout: 3), "the GIF tool opens the GIF panel")
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.gif.'"))
        XCTAssertTrue(tile.firstMatch.waitForExistence(timeout: 15), "an empty search shows KLIPY's trending GIFs")
        try shot("gif")

        for letter in "cat" { key(String(letter), in: app).tap() }
        let search = app.descendants(matching: .any).matching(identifier: "iikb.panel.search").firstMatch
        XCTAssertTrue(wait { (search.value as? String) == "cat" }, "the keys type into the search")
        XCTAssertTrue(wait(15) { tile.count > 4 }, "searching finds GIFs")
        try shot("gif-search")
        if compact { assertOneRowScrollsSideways(tile, in: gifs, app: app) }

        let picked = tile.element(boundBy: 0)
        let id = picked.identifier.components(separatedBy: "--")[0]
        picked.tap()
        XCTAssertTrue(wait(15) { (search.value as? String)?.hasPrefix("Copied") == true }, "a tap says it was copied")
        XCTAssertTrue(UIPasteboard.general.contains(pasteboardTypes: [UTType.gif.identifier]), "the GIF is on the clipboard")
        try shot("gif-copied")

        app.buttons["iikb.gifs.recents"].tap()
        XCTAssertTrue(wait(15) { tile.firstMatch.identifier == id }, "the clock shows the GIF you sent first")
        try shot("gif-recents")
    }

    func testAHeldGifDragsIntoTheMessage() throws {
        guard FileManager.default.fileExists(atPath: (ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? "") + "/Applications/MobileSMS.app") else {
            throw XCTSkip("this simulator has no Messages: iOS 27.1, the only one with the iPhone Duo, leaves it out")
        }
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.launch()
        let thread = messages.cells.firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Messages shows a conversation")
        thread.tap()
        let field = messages.textFields["messageBodyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the conversation has a message field")
        field.tap()
        XCTAssertTrue(key("space", in: messages).waitForExistence(timeout: 20), "iikb is not the active keyboard")
        messages.buttons["iikb.tool.gif"].tap()
        let tile = messages.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.gif.'"))
        XCTAssertTrue(tile.firstMatch.waitForExistence(timeout: 15), "an empty search shows KLIPY's trending GIFs")
        try shot("gif-drag")

        let picked = tile.firstMatch
        let id = picked.identifier.components(separatedBy: "--")[0]
        picked.press(forDuration: 1, thenDragTo: field, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(wait(15) { (field.value as? String)?.contains("\u{FFFC}") == true }, "the GIF is in the message")
        let search = messages.descendants(matching: .any).matching(identifier: "iikb.panel.search").firstMatch
        XCTAssertFalse((search.value as? String)?.hasPrefix("Copied") == true, "a drag doesn't also copy")
        try shot("gif-dropped")
        messages.buttons["iikb.gifs.recents"].tap()
        XCTAssertTrue(wait(15) { tile.firstMatch.identifier == id }, "the clock shows the GIF you dropped first")
        messages.terminate()
    }

    func testTheClipboardPanelKeepsWhatYouCopyAndTypesWhatYouPick() throws {
        UIPasteboard.general.string = "Meet at Sightglass on 7th, 4pm?"
        var app = launch()
        let tool = app.buttons["iikb.tool.clipboard"]
        XCTAssertTrue(tool.waitForExistence(timeout: 3))
        tool.tap()
        app.buttons["iikb.edit.history"].tap()
        let message = app.buttons["iikb.clipboard.message"]
        if message.waitForExistence(timeout: 2), message.label.contains("Paste from Other Apps") {
            try shot("clipboard-refused")
            message.tap()
            sleep(2)
            try shot("clipboard-settings")
            try allowPasteFromOtherApps()
            app = launch()
            tool.tap()
            app.buttons["iikb.edit.history"].tap()
        }
        let row = app.descendants(matching: .any).matching(identifier: "iikb.clip.Meet at Sightglass on 7th, 4pm?").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "what you copied in another app is kept")
        XCTAssertTrue(row.staticTexts["iikb.clip.detail"].label.hasPrefix("31 chars · "), "a row says how long its text is, then how long ago")
        try shot("clipboard")

        for letter in "sight" { key(String(letter), in: app).tap() }
        XCTAssertTrue(row.exists, "the search finds it by its text")
        row.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait { (field.value as? String)?.contains("Meet at Sightglass on 7th, 4pm?") == true }, "a tap types it into the app")
        app.buttons["iikb.panel.clear"].tap()

        row.press(forDuration: 0.8)
        let pin = app.buttons["iikb.clipboard.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3), "holding a row offers Pin and Delete")
        try shot("clipboard-hold")
        let before = pin.label
        pin.tap()
        XCTAssertTrue(wait { !pin.exists }, "Pin closes the actions")
        row.press(forDuration: 0.8)
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        XCTAssertEqual(pin.label, before == "Pin" ? "Unpin" : "Pin", "Pin and Unpin take turns")
        pin.label == "Pin" ? pin.tap() : row.tap()
        XCTAssertTrue(wait { !pin.exists })
        try shot("clipboard-pinned")
    }

    func testTheClipboardButtonLetsOutCutCopyAndPasteAndTucksThemBackOnceUsed() throws {
        UIPasteboard.general.string = "Sightglass"
        let app = launch()
        let field = app.textViews.firstMatch
        let tool = app.buttons["iikb.tool.clipboard"]
        XCTAssertTrue(tool.waitForExistence(timeout: 3))
        for letter in "hi" { key(String(letter), in: app).tap() }
        key("space", in: app).tap()
        let paste = app.buttons["iikb.edit.paste"], cut = app.buttons["iikb.edit.cut"]
        XCTAssertFalse(paste.isHittable, "the tray is tucked into the clipboard's button")
        tool.tap()
        XCTAssertTrue(wait { paste.isHittable }, "the clipboard's button lets out its tray")
        XCTAssertFalse(cut.isEnabled, "nothing selected, nothing to cut")
        try shot("tray")
        paste.tap()
        XCTAssertTrue(wait { (field.value as? String)?.hasSuffix("hi Sightglass") == true }, "Paste types what's on the clipboard")
        XCTAssertTrue(wait { !paste.isHittable }, "and the tray tucks back in")

        tool.tap()
        XCTAssertTrue(wait { paste.isHittable })
        key("a", in: app).tap()
        XCTAssertTrue(wait { !paste.isHittable }, "a key tucks the tray back in")

        field.doubleTap()
        tool.tap()
        XCTAssertTrue(wait { cut.isHittable && cut.isEnabled }, "with a selection, Cut and Copy can")
        try shot("tray-selected")
        cut.tap()
        XCTAssertTrue(wait { (field.value as? String)?.contains("Sightglass") == false }, "Cut takes the selection out")
        tool.tap()
        XCTAssertTrue(wait { paste.isHittable && paste.isEnabled })
        paste.tap()
        XCTAssertTrue(wait { (field.value as? String)?.contains("Sightglass") == true }, "and Paste puts back what Cut copied")
    }

    func testTranscriptsOpenFromTheClipboardsTrayAndTypeWhatYouPick() throws {
        let app = launch()
        let tool = app.buttons["iikb.tool.clipboard"]
        XCTAssertTrue(tool.waitForExistence(timeout: 3))
        tool.tap()
        app.buttons["iikb.edit.transcripts"].tap()
        XCTAssertTrue(app.collectionViews["iikb.transcripts"].waitForExistence(timeout: 3), "the tray opens Transcripts")
        let row = app.descendants(matching: .any).matching(identifier: "iikb.transcript.0").firstMatch
        guard row.waitForExistence(timeout: 5) else {
            XCTAssertTrue(app.buttons["iikb.transcripts.message"].exists, "with nothing dictated, the drawer says so")
            return try shot("transcripts-empty")
        }
        XCTAssertTrue(row.staticTexts["iikb.clip.detail"].label.contains(" words · ") || row.staticTexts["iikb.clip.detail"].label.contains(" word · "), "a row says its words, then how long ago")
        try shot("transcripts")
        let text = row.staticTexts["iikb.clip.text"].label
        row.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait { (field.value as? String)?.contains(text.prefix(20)) == true }, "a tap types it into the app")
        app.buttons["iikb.transcripts.clipboard"].tap()
        XCTAssertTrue(app.collectionViews["iikb.clipboard"].waitForExistence(timeout: 3), "the field's button switches to the clipboard")
        try shot("transcripts-to-clipboard")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", orientation, "-iikbOneHanded", "off", "-iikbCompactPanels", compactSetting ? "YES" : "NO"]
        app.launch()
        if !key("space", in: app).waitForExistence(timeout: 20) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 30), "iikb is not the active keyboard")
        return app
    }

    private func wait(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private var orientation: String { ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] ?? "portrait" }
    /// `IIKB_COMPACT=1` turns on Compact Emoji & GIFs.
    private var compactSetting: Bool { ProcessInfo.processInfo.environment["IIKB_COMPACT"] == "1" }
    /// Landscape, or the setting, shows the panels as one row.
    private var compact: Bool { compactSetting || orientation == "landscape" }

    /// The results sit in one row, and a swipe moves them sideways.
    private func assertOneRowScrollsSideways(_ tiles: XCUIElementQuery, in scroller: XCUIElement, app: XCUIApplication) {
        let row = (0..<min(tiles.count, 8)).map { tiles.element(boundBy: $0).frame }
        XCTAssertEqual(Set(row.map(\.minY)).count, 1, "the GIFs are one row")
        let first = tiles.element(boundBy: 0)
        let start = first.frame.minX
        scroller.swipeLeft()
        XCTAssertTrue(wait(5) { first.frame.minX < start - 40 }, "a swipe scrolls the row sideways")
        scroller.swipeRight()
        _ = wait(5) { first.frame.minX == start }
    }

    private func shot(_ name: String) throws {
        guard let shots else { return }
        Thread.sleep(forTimeInterval: 1.5)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)-\(name).png"))
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
