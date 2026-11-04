import XCTest

/// Types each line of a file through the simulator's keyboard and records its suggestion bar before each word and after
/// its first and second letters, for comparing bars: HEX_APPLEBAR_IN (one lowercase segment per line), HEX_APPLEBAR_OUT.
final class AppleBar: XCTestCase {
    func testBars() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["HEX_APPLEBAR_IN"], let output = environment["HEX_APPLEBAR_OUT"] else { throw XCTSkip("Run through scripts/applebar") }
        let first = Int(environment["HEX_APPLEBAR_FIRST"] ?? "") ?? 0
        let count = Int(environment["HEX_APPLEBAR_COUNT"] ?? "") ?? .max
        let lines = try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n").map(String.init)
        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", "portrait"]
        app.launch()
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keys.matching(NSPredicate(format: "label ==[c] 'a'")).firstMatch.waitForExistence(timeout: 10))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        var keys: [String: CGPoint] = [:]
        for key in app.keyboards.firstMatch.descendants(matching: .any).allElementsBoundByIndex where key.frame.width > 0 && !key.label.isEmpty {
            let frame = key.frame
            keys[key.label.lowercased()] = CGPoint(x: frame.midX, y: frame.midY)
        }
        let more = keys["more"] ?? keys["numbers"] ?? keys["123"]
        XCTAssertNotNil(more, "keys: \(keys.keys.sorted())")
        func tap(_ point: CGPoint) { origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap() }
        if let more {
            tap(more)
            Thread.sleep(forTimeInterval: 0.5)
            for key in app.keys.allElementsBoundByIndex where ["'", "apostrophe"].contains(key.label.lowercased()) {
                keys["'"] = CGPoint(x: key.frame.midX, y: key.frame.midY)
            }
            tap(more)
        }
        XCTAssertNotNil(keys["'"])
        let newline = try XCTUnwrap(keys["return"] ?? keys["new line"], "keys: \(keys.keys.sorted())")
        let bar = app.otherElements["Typing Predictions"]
        func read() -> [String] {
            guard let snapshot = try? bar.snapshot() else { return [] }
            var labels: [String] = []
            func walk(_ node: XCUIElementSnapshot) {
                if node.elementType == .button { labels.append(node.label) }
                node.children.forEach(walk)
            }
            walk(snapshot)
            return labels
        }
        func settle(_ done: ([String]) -> Bool) -> [String] {
            var labels = read()
            let start = Date()
            while !done(labels), Date().timeIntervalSince(start) < 1.5 {
                Thread.sleep(forTimeInterval: 0.1)
                labels = read()
            }
            return labels
        }
        var out = ""
        var last: [String] = []
        for (index, line) in lines.enumerated() where index >= first && index < first + count {
            if index > first { tap(newline) }
            for (position, word) in line.split(separator: " ").enumerated() {
                var bars: [[String]] = []
                bars.append(settle { $0 != last && !$0.contains { $0.hasPrefix("“") } })
                for (offset, character) in word.enumerated() {
                    guard let point = keys[String(character)] else { continue }
                    tap(point)
                    if offset < 2 {
                        let typed = "“" + word.prefix(offset + 1) + "”"
                        bars.append(settle { $0.contains(typed) || ($0.first.map { !$0.hasPrefix("“") } ?? false) })
                    }
                }
                tap(keys["space"]!)
                last = bars.last ?? []
                out += "\(index)|\(position)|\(word)|" + bars.map { $0.joined(separator: ",") }.joined(separator: "|") + "\n"
            }
            try out.write(toFile: output, atomically: true, encoding: .utf8)
        }
    }
}
