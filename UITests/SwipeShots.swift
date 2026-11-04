import XCTest

/// Swipes a word and screenshots the trail as the finger lifts and the bar a moment later: HEX_SHOTS is the file prefix,
/// HEX_SWIPE_ORIENTATION (portrait, landscape) the screen's.
final class SwipeShots: XCTestCase {
    func testSwipeAndShoot() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let prefix = environment["HEX_SHOTS"] else { throw XCTSkip("Run through scripts/swipeshots") }
        let landscape = environment["HEX_SWIPE_ORIENTATION"] == "landscape"
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", landscape ? "landscape" : "portrait"]
        app.launch()
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 10))

        let centers = "keyboard".map { letter -> CGPoint in
            let frame = key(String(letter), in: app).frame
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        let finger = XCPointerEventPath(forTouchAt: centers[0], offset: 0.05)
        var time = 0.05
        for (from, to) in zip(centers, centers.dropFirst()) {
            let steps = max(Int(hypot(to.x - from.x, to.y - from.y) / 6), 1)
            for step in 1...steps {
                time += 0.01
                let share = Double(step) / Double(steps)
                finger.move(to: CGPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share), atOffset: time)
            }
        }
        finger.liftUp(atOffset: time + 0.02)
        let record = XCSynthesizedEventRecord(name: "keyboard", interfaceOrientation: landscape ? .landscapeRight : .portrait)
        record.add(finger)
        try record.synthesize()
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-trail.png"))
        Thread.sleep(forTimeInterval: 1.5)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-bar.png"))
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.keys.matching(identifier: "hex.\(name)").firstMatch
    }
}
