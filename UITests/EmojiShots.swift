import XCTest

/// Screenshots of the emoji keyboard, Apple's or Hex's, for `scripts/mac 'scripts/emojishots …'`: opened, scrolled, on
/// Food & Drink, and searching for "heart".
final class EmojiShots: XCTestCase {
    func testOpenScrollAndShoot() throws {
        guard let prefix = ProcessInfo.processInfo.environment["HEX_SHOTS"] else { throw XCTSkip("Run through scripts/emojishots") }
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        let numbers = app.keys.matching(identifier: "hex.numbers").firstMatch
        if numbers.waitForExistence(timeout: 6) {
            numbers.press(forDuration: 0.8)
        } else {
            let frame = app.frame
            app.coordinate(withNormalizedOffset: CGVector(dx: 42 / frame.width, dy: (frame.height - 40) / frame.height)).tap()
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
        try shoot("open")
        let grid = app.collectionViews.firstMatch
        if grid.exists {
            grid.swipeLeft()
            try shoot("scrolled")
        }
        let food = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Food'")).firstMatch
        if food.exists {
            food.tap()
            try shoot("food")
        }
        let hex = app.descendants(matching: .any).matching(identifier: "hex.emoji.search").firstMatch
        let search = hex.exists ? hex : app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'Search' OR label CONTAINS[c] 'Search'")).firstMatch
        if search.exists {
            search.tap()
            try shoot("search")
            for letter in "heart" {
                let key = app.keys.matching(identifier: "hex.\(letter)").firstMatch
                (key.exists ? key : app.keys.matching(NSPredicate(format: "label ==[c] %@", String(letter))).firstMatch).tap()
            }
            try shoot("search-heart")
        }
    }
}
