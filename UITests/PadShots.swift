import XCTest

/// Every state of the keyboard on one screen, through the real extension, for checking a layout on iPad (scripts/padshots):
/// typing with suggestions, the number and symbol layers, the clipboard's tray, the More menu, the emoji, GIF, clipboard and
/// Transcripts panels, and the keyboard pinched to float. Screenshots go to `IIKB_SHOTS-<state>.png`; a state the screen
/// doesn't have is left out.
final class PadShots: XCTestCase {
    func testEveryState() throws {
        let prefix = try XCTUnwrap(ProcessInfo.processInfo.environment["IIKB_SHOTS"])
        let only = ProcessInfo.processInfo.environment["IIKB_STATES"].flatMap { $0.isEmpty ? nil : Set($0.split(separator: " ").map(String.init)) }
        func wanted(_ state: String) -> Bool { only?.contains(state) ?? true }
        func shot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.8)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        }
        let app = XCUIApplication()
        app.launchArguments = ["-iikbFocus", "YES", "-iikbOrientation", ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] ?? "portrait", "-iikbOneHanded", "off"]
        app.launch()
        XCUIDevice.shared.orientation = ProcessInfo.processInfo.environment["IIKB_ORIENTATION"] == "landscape" ? .landscapeLeft : .portrait
        let space = key("space", in: app)
        XCTAssertTrue(space.waitForExistence(timeout: 30), "iikb is not the active keyboard")
        try shot("empty")
        try app.debugDescription.write(toFile: "\(prefix)-empty.txt", atomically: true, encoding: .utf8)
        for letter in "coffee at" { key(letter == " " ? "space" : String(letter), in: app).tap() }
        try shot("main")

        if wanted("layers"), key("numbers", in: app).exists {
            key("numbers", in: app).tap()
            try shot("numbers")
            if key("symbols", in: app).exists {
                key("symbols", in: app).tap()
                try shot("symbols")
            }
            if key("letters", in: app).exists { key("letters", in: app).tap() }
        }
        if wanted("tray"), app.buttons["iikb.tool.clipboard"].exists {
            app.buttons["iikb.tool.clipboard"].tap()
            try shot("tray")
            app.buttons["iikb.tool.clipboard"].tap()
        }
        if wanted("more"), app.buttons["iikb.more"].exists {
            app.buttons["iikb.more"].tap()
            try shot("more")
            app.buttons["iikb.more"].tap()
            Thread.sleep(forTimeInterval: 0.5)
            if !space.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap() }
        }
        for (panel, tool) in [("emoji", "iikb.tool.emoji"), ("gif", "iikb.tool.gif")] where wanted(panel) {
            let button = app.buttons[tool].exists ? app.buttons[tool] : key("emoji", in: app)
            guard button.exists else { continue }
            button.tap()
            Thread.sleep(forTimeInterval: panel == "gif" ? 4 : 1)
            try shot(panel)
            app.buttons["iikb.panel.back"].tap()
        }
        if wanted("clipboard"), app.buttons["iikb.tool.clipboard"].exists {
            app.buttons["iikb.tool.clipboard"].tap()
            app.buttons["iikb.edit.history"].tap()
            try shot("clipboard")
            app.buttons["iikb.panel.back"].tap()
        }
        if wanted("floating"), key("g", in: app).exists {
            key("g", in: app).pinch(withScale: 0.4, velocity: -2)
            Thread.sleep(forTimeInterval: 2)
            try shot("floating")
            print("FLOATING space \(space.exists ? space.frame.debugDescription : "gone")")
        }
    }

    private func key(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.keys.matching(NSPredicate(format: "identifier == %@ OR label ==[c] %@", "iikb.\(name)", name)).firstMatch
    }
}
