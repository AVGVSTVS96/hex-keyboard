import XCTest

/// The emoji panel through the real keyboard: the emoji key opens it, the keys type into its search, a tap types the emoji
/// into the app, and back brings the bar back. With HEX_SHOTS set, screenshots each step.
final class PanelTests: XCTestCase {
    func testTheEmojiPanelSearchesWithTheKeysAndTypesWhatYouPick() throws {
        let shots = ProcessInfo.processInfo.environment["HEX_SHOTS"]
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", orientation, "-HexOneHanded", "off", "-HexCompactPanels", compactSetting ? "YES" : "NO"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 30), "Hex keyboard is not the active keyboard")
        for letter in "coffee at" { key(letter == " " ? "space" : String(letter), in: app).tap() }
        try shot(shots, "main")

        let tool = key("emoji", in: app)
        XCTAssertTrue(tool.waitForExistence(timeout: 3), "the emoji key sits beside the space bar")
        tool.tap()
        let grid = app.collectionViews["hex.emoji"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3), "the emoji key opens the emoji panel")
        try shot(shots, "emoji")
        if compact { try assertOneRowScrollsSideways(grid.cells, in: grid, app: app) }

        for letter in "pizza" { key(String(letter), in: app).tap() }
        let search = app.descendants(matching: .any).matching(identifier: "hex.panel.search").firstMatch
        XCTAssertTrue(wait { (search.value as? String) == "pizza" }, "the keys type into the search, not the app")
        let field = app.textViews.firstMatch
        XCTAssertEqual(field.value as? String, "Coffee at")
        let pizza = app.descendants(matching: .any).matching(identifier: "hex.emoji.🍕").firstMatch
        XCTAssertTrue(pizza.waitForExistence(timeout: 3), "searching finds the emoji by name")
        try shot(shots, "search")

        pizza.tap()
        XCTAssertTrue(wait { (field.value as? String) == "Coffee at🍕" }, "a tap types the emoji into the app")
        app.buttons["hex.panel.back"].tap()
        XCTAssertTrue(wait { tool.exists && !grid.exists }, "back brings the bar and the tools back")
        try shot(shots, "after")
    }

    func testHoldingDeleteToEmptyTheSearchLeavesTheMessageAlone() throws {
        let app = launchAndType("coffee at")
        openEmoji(in: app)
        for letter in "pizza" { key(String(letter), in: app).tap() }
        let search = app.descendants(matching: .any).matching(identifier: "hex.panel.search").firstMatch
        XCTAssertTrue(wait { (search.value as? String) == "pizza" })
        key("delete", in: app).press(forDuration: 3)
        XCTAssertTrue(wait { (search.value as? String) == "" }, "holding delete empties the search")
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "Coffee at", "and stops there, before the message")
    }

    func testHoldingAnEmojiAtTheRightEdgeWithoutSlidingPicksIt() throws {
        let app = launchAndType("hi ")
        openEmoji(in: app)
        for letter in "hand" { key(String(letter), in: app).tap() }
        let cells = app.collectionViews["hex.emoji"].cells
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 3))
        let top = cells.firstMatch.frame.minY
        let row = (0..<min(cells.count, 20)).map { cells.element(boundBy: $0) }.filter { $0.frame.minY == top }
        let edge = try XCTUnwrap(row.max { $0.frame.maxX < $1.frame.maxX })
        let emoji = edge.label
        edge.press(forDuration: 1)
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait { (field.value as? String) != "Hi " })
        XCTAssertEqual(field.value as? String, "Hi " + emoji, "letting go where the hold began picks the emoji held")
    }

    private var orientation: String { ProcessInfo.processInfo.environment["HEX_ORIENTATION"] ?? "portrait" }
    /// `HEX_COMPACT=1` turns on Compact Emoji & GIFs.
    private var compactSetting: Bool { ProcessInfo.processInfo.environment["HEX_COMPACT"] == "1" }
    /// Landscape, or the setting, shows the panels as one row.
    private var compact: Bool { compactSetting || orientation == "landscape" }

    private func launchAndType(_ text: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait", "-HexOneHanded", "off"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 30), "Hex keyboard is not the active keyboard")
        for letter in text { key(letter == " " ? "space" : String(letter), in: app).tap() }
        return app
    }

    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func shot(_ prefix: String?, _ name: String) throws {
        guard let prefix else { return }
        Thread.sleep(forTimeInterval: 0.8)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.keys.matching(NSPredicate(format: "identifier == %@ OR label ==[c] %@", "hex.\(name)", name)).firstMatch
    }

    /// The results sit in one row, and a swipe moves them sideways.
    private func assertOneRowScrollsSideways(_ cells: XCUIElementQuery, in scroller: XCUIElement, app: XCUIApplication) throws {
        let row = (0..<min(cells.count, 12)).map { cells.element(boundBy: $0).frame }
        XCTAssertGreaterThan(row.count, 4)
        XCTAssertEqual(Set(row.map(\.minY)).count, 1, "the results are one row")
        let first = cells.element(boundBy: 0)
        let id = first.identifier
        let start = first.frame.minX
        scroller.swipeLeft()
        let moved = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(wait { !moved.exists || moved.frame.minX < start - 40 }, "a swipe scrolls the row sideways")
        scroller.swipeRight()
    }

    private func openEmoji(in app: XCUIApplication) {
        let emoji = key("emoji", in: app)
        XCTAssertTrue(emoji.waitForExistence(timeout: 5), "the emoji key sits beside the space bar")
        emoji.tap()
    }
}
