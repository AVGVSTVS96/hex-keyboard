import XCTest

/// Emoji in the suggestion bar and the emoji keyboard's search, through the real keyboard. With HEX_SHOTS set (by
/// `scripts/emojishots`), it screenshots the bar's emoji.
final class EmojiSearchTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOneHanded", "off", "-HexOrientation", "portrait"]
        app.launch()
        XCTAssertTrue(key("space").waitForExistence(timeout: 10), "Hex keyboard is not the active keyboard")
    }

    private var field: XCUIElement { app.textViews.firstMatch }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "hex.\(name)").firstMatch
    }

    private func type(_ text: String) {
        for character in text { key(character == " " ? "space" : String(character)).tap() }
    }

    private func shoot(_ name: String) throws {
        guard let prefix = ProcessInfo.processInfo.environment["HEX_SHOTS"] else { return }
        Thread.sleep(forTimeInterval: 1.2)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
    }

    func testTheBarsLastSlotOffersEmojiForTheWordAndTapsTypeThem() throws {
        type("i love pizza")
        let pizza = app.keys.matching(identifier: "hex.suggestion.emoji.0").firstMatch
        XCTAssertTrue(pizza.waitForExistence(timeout: 3))
        XCTAssertEqual(pizza.label, "🍕")
        XCTAssertFalse(app.keys.matching(identifier: "hex.suggestion.2").firstMatch.exists, "the emoji take the last slot")
        try shoot("bar")
        pizza.tap()
        XCTAssertEqual(field.value as? String, "I love 🍕 ")

        type("my dog ")
        let dog = app.keys.matching(identifier: "hex.suggestion.emoji.0").firstMatch
        XCTAssertTrue(dog.waitForExistence(timeout: 3), "the word just typed still offers its emoji")
        try shoot("bar-after-space")
        let emoji = dog.label
        dog.tap()
        XCTAssertEqual(field.value as? String, "I love 🍕 my dog \(emoji) ")
    }

    func testSearchingEmojiTypesIntoTheSearchAndPicksTypeIntoTheText() throws {
        key("numbers").press(forDuration: 0.8)
        let search = app.descendants(matching: .any).matching(identifier: "hex.emoji.search").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        let results = app.collectionViews.matching(identifier: "hex.emoji.results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 2))
        XCTAssertTrue(key("q").exists, "the letters type into the search")

        type("heart")
        XCTAssertEqual(search.value as? String, "heart")
        XCTAssertEqual(field.value as? String ?? "", "", "the letters stay out of the text")
        let first = results.cells.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        XCTAssertEqual(first.label, "❤️")
        first.tap()
        XCTAssertEqual(field.value as? String, "❤️")

        key("delete").tap()
        XCTAssertEqual(search.value as? String, "hear")
        app.buttons.matching(identifier: "hex.emoji.search.clear").firstMatch.tap()
        XCTAssertEqual(search.value as? String ?? "", "")

        key("return").tap()
        XCTAssertTrue(app.collectionViews.matching(identifier: "hex.emoji").firstMatch.waitForExistence(timeout: 2), "the checkmark goes back to the emoji")
        app.buttons.matching(identifier: "hex.abc").firstMatch.tap()
        XCTAssertTrue(key("q").waitForExistence(timeout: 2))
        type("hi")
        XCTAssertEqual(field.value as? String, "❤️hi")
    }
}
