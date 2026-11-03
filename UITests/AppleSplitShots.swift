import XCTest

/// Apple's keyboard on the open iPhone Duo held wide, split from its … menu, in letters, 123 and #+=: the reference Hex's
/// split is matched against. HEX_SPLIT_SHOTS names the files; the simulator types with Apple's keyboard (scripts/sim use).
final class AppleSplitShots: XCTestCase {
    func testApplesSplitKeyboard() throws {
        guard let prefix = ProcessInfo.processInfo.environment["HEX_SPLIT_SHOTS"] else { throw XCTSkip("Run with HEX_SPLIT_SHOTS") }
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES"]
        app.launch()
        let q = app.keys.matching(NSPredicate(format: "label ==[c] 'q'")).firstMatch
        XCTAssertTrue(q.waitForExistence(timeout: 15), "Apple's keyboard is up")
        func shot(_ name: String) throws {
            sleep(1)
            try app.debugDescription.write(toFile: "\(prefix)-\(name).txt", atomically: true, encoding: .utf8)
            for (index, screen) in XCUIScreen.screens.enumerated() {
                try screen.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name)-\(index).png"))
            }
        }
        try shot("full")
        let more = app.buttons.matching(NSPredicate(format: "label ==[c] 'more' OR identifier ==[c] 'more'")).firstMatch
        if more.exists {
            more.tap()
        } else {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 42, dy: 430)).tap()
        }
        try shot("menu")
        let split = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] 'split'")).firstMatch
        guard split.waitForExistence(timeout: 5) else { return }
        split.tap()
        try shot("split")
        let numbers = app.keys.matching(NSPredicate(format: "label ==[c] 'numbers' OR label == '123'")).firstMatch
        guard numbers.waitForExistence(timeout: 5) else { return }
        numbers.tap()
        try shot("split-123")
        let symbols = app.keys.matching(NSPredicate(format: "label ==[c] 'symbols' OR label == '#+='")).firstMatch
        if symbols.waitForExistence(timeout: 5) {
            symbols.tap()
            try shot("split-symbols")
        }
    }
}
