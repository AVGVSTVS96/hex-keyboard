import XCTest

/// Swipes a word through the real extension with one synthesized touch that never lifts between letters, and checks
/// what's typed, the bar after it, and delete.
final class SwipeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexResetSettings", "YES"]
        app.launch()
        if !app.keys["hex.space"].waitForExistence(timeout: 15) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.keys["hex.space"].waitForExistence(timeout: 15), "iikb is not the active keyboard")
    }

    func testASwipeTypesItsWordAndTheBarOffersOthers() throws {
        try swipe("world")
        XCTAssertEqual(settled().lowercased(), "world")
        XCTAssertTrue(suggestion(0).waitForExistence(timeout: 5))
        let others = (0..<3).map(suggestion).filter(\.exists).map(\.label)
        XCTAssertFalse(others.map { $0.lowercased() }.contains("world"), "the bar offers other words, as Apple's does after a swipe")
        let alternative = try XCTUnwrap(others.first, "no alternative offered")
        suggestion(0).tap()
        XCTAssertEqual(settled().trimmingCharacters(in: .whitespaces).lowercased(), alternative.lowercased())
    }

    func testDeleteRightAfterASwipeTakesTheWholeWord() throws {
        try swipe("world")
        XCTAssertFalse(settled().isEmpty)
        key("delete").tap()
        XCTAssertEqual(settled(), "")
    }

    func testASwipeAfterAWordFollowsASpace() throws {
        try swipe("world")
        try swipe("keyboard")
        XCTAssertEqual(settled().lowercased(), "world keyboard")
    }

    func testATapThatWandersStaysATap() throws {
        let center = center(of: "g")
        let path = XCPointerEventPath(forTouchAt: center, offset: 0.05)
        path.move(to: CGPoint(x: center.x + 8, y: center.y + 4), atOffset: 0.07)
        path.liftUp(atOffset: 0.1)
        let record = XCSynthesizedEventRecord(name: "wander", interfaceOrientation: .portrait)
        record.add(path)
        try record.synthesize()
        XCTAssertEqual(settled().lowercased(), "g")
    }

    func testADragFromKeyToKeyTypesAWordOnEveryScreen() {
        let middle = CGVector(dx: 0.5, dy: 0.5)
        key("t").coordinate(withNormalizedOffset: middle)
            .press(forDuration: 0.05, thenDragTo: key("o").coordinate(withNormalizedOffset: middle), withVelocity: 600, thenHoldForDuration: 0)
        XCTAssertEqual(settled().lowercased(), "to")
    }

    private func swipe(_ word: String) throws {
        let centers = word.map { center(of: String($0)) }
        let finger = XCPointerEventPath(forTouchAt: centers[0], offset: 0.05)
        var time = 0.05
        for (from, to) in zip(centers, centers.dropFirst()) {
            let steps = max(Int(hypot(to.x - from.x, to.y - from.y) / 6), 1)
            if steps == 1 && from == to { time += 0.12 }
            for step in 1...steps {
                time += 0.01
                let share = Double(step) / Double(steps)
                finger.move(to: CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share), atOffset: time)
            }
        }
        finger.liftUp(atOffset: time + 0.02)
        let record = XCSynthesizedEventRecord(name: word, interfaceOrientation: .portrait)
        record.add(finger)
        try record.synthesize()
    }

    private func center(of letter: String) -> CGPoint {
        let frame = key(letter).frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func key(_ name: String) -> XCUIElement {
        app.keys.matching(identifier: "hex.\(name)").firstMatch
    }

    private func suggestion(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "hex.suggestion.\(index)").firstMatch
    }

    private func settled() -> String {
        var last = app.textViews.firstMatch.value as? String ?? ""
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = app.textViews.firstMatch.value as? String ?? ""
            if now == last { return now }
            last = now
        }
        return last
    }
}
