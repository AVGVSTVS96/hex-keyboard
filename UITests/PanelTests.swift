import XCTest

/// The emoji panel through the real keyboard: the pill opens it, the keys type into its search, a tap types the emoji
/// into the app, and back brings the bar and pills back. With HEX_SHOTS set, screenshots each step.
final class PanelTests: XCTestCase {
    func testTheEmojiPanelSearchesWithTheKeysAndTypesWhatYouPick() throws {
        let shots = ProcessInfo.processInfo.environment["HEX_SHOTS"]
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", ProcessInfo.processInfo.environment["HEX_ORIENTATION"] ?? "portrait", "-HexOneHanded", "off"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 30), "Hex keyboard is not the active keyboard")
        for letter in "coffee at" { key(letter == " " ? "space" : String(letter), in: app).tap() }
        try shot(shots, "main")

        let tool = app.buttons["hex.tool.emoji"]
        XCTAssertTrue(tool.waitForExistence(timeout: 3), "the emoji tool sits under the bar, or at its left end")
        tool.tap()
        let grid = app.collectionViews["hex.emoji"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3), "the emoji pill opens the emoji panel")
        try shot(shots, "emoji")

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
        let hex = app.keys.matching(identifier: "hex.\(name)").firstMatch
        return hex.exists ? hex : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
