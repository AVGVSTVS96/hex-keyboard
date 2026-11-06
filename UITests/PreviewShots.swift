import XCTest

/// The link preview's frames (brand/og): the keyboard in landscape typing, swiping, picking an emoji and a GIF and
/// dictating, one screenshot per step, each named for how long it holds in the video. Run through scripts/previewshots.
final class PreviewShots: XCTestCase {
    private var prefix = ""
    private var frame = 0

    func testTheKeyboardDoesEverythingOnce() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let shots = environment["IIKB_SHOTS"] else { throw XCTSkip("Run through scripts/previewshots") }
        prefix = shots
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", "landscape", "-iikbOneHanded", "off", "-iikbMicKey", "NO"]
        app.launch()
        if !key("space", in: app).waitForExistence(timeout: 20) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(key("space", in: app).waitForExistence(timeout: 30), "iikb is not the active keyboard")
        try shot(500)

        for letter in "the best ios keyboard " {
            key(letter == " " ? "space" : String(letter), in: app).tap()
            try shot(letter == " " ? 120 : 60)
        }

        try swipe("world", in: app)
        try shot(260, settle: 0.1)
        try shot(380)

        key("emoji", in: app).tap()
        XCTAssertTrue(app.collectionViews["iikb.emoji"].waitForExistence(timeout: 3))
        try shot(320)
        for letter in "fire" {
            key(String(letter), in: app).tap()
            try shot(80)
        }
        let fire = app.descendants(matching: .any).matching(identifier: "iikb.emoji.🔥").firstMatch
        XCTAssertTrue(fire.waitForExistence(timeout: 3))
        fire.tap()
        try shot(380)
        app.buttons["iikb.panel.back"].tap()

        let gif = app.buttons["iikb.tool.gif"]
        XCTAssertTrue(gif.waitForExistence(timeout: 3), "the GIF tool shows when a KLIPY key is built in")
        gif.tap()
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'iikb.gif.'"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 15))
        try shot(320, settle: 2.5)
        for letter in "wow" {
            key(String(letter), in: app).tap()
            try shot(80, settle: 0.3)
        }
        XCTAssertTrue(wait(15) { tiles.count > 4 })
        try shot(520, settle: 3)
        app.buttons["iikb.panel.back"].tap()

        let mic = app.buttons["iikb.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()
        XCTAssertTrue(wait { mic.label == "Stop Dictating" })
        for _ in 0..<8 { try shot(130, settle: 0.25) }
        mic.tap()
        let field = app.textViews.firstMatch
        XCTAssertTrue(wait(15) { (field.value as? String ?? "").contains("say") })
        try shot(1200)
    }

    private func swipe(_ word: String, in app: XCUIApplication) throws {
        let centers = word.map { letter -> CGPoint in
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
        let record = XCSynthesizedEventRecord(name: word, interfaceOrientation: .landscapeRight)
        record.add(finger)
        try record.synthesize()
    }

    /// Saves the screen as `<prefix>-<frame>-<ms>.png`, `ms` being how long the frame holds in the video.
    private func shot(_ ms: Int, settle: TimeInterval = 0.6) throws {
        Thread.sleep(forTimeInterval: settle)
        let name = String(format: "%@-%03d-%d.png", prefix, frame, ms)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: name))
        frame += 1
    }

    private func wait(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let iikb = app.keys.matching(identifier: "iikb.\(name)").firstMatch
        return iikb.exists ? iikb : app.keys.matching(NSPredicate(format: "label ==[c] %@", name)).firstMatch
    }
}
