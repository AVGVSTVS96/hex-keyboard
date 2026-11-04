import XCTest

/// Replays recorded human swipes (scripts/swipebench.tsv) through the simulator's keyboard, each as one continuous touch
/// with its original timing, and records the word typed and the bar: HEX_SWIPE_IN, HEX_SWIPE_OUT, HEX_SWIPE_FIRST,
/// HEX_SWIPE_COUNT, HEX_SWIPE_ORIENTATION (portrait, landscape).
final class SwipeBench: XCTestCase {
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let rowStart: [Double] = [0.05, 0.1004672897196, 0.2004672897196]
    private static let rowCenter: [Double] = [1.0 / 6, 0.5, 5.0 / 6]

    private typealias Point = (x: Double, y: Double, t: Double)

    private static func load(_ path: String) throws -> [(String, [Point])] {
        var swipes: [(String, [Point])] = []
        for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            var points: [Point] = []
            for triple in fields[1].split(separator: ";") {
                let values: [Double] = triple.split(separator: ",").map { Double($0) ?? 0 }
                points.append(Point(x: values[0] / 1000, y: values[1] / 1000, t: values[2] / 1000))
            }
            swipes.append((String(fields[0]), points))
        }
        return swipes
    }

    func testSwipes() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["HEX_SWIPE_IN"], let output = environment["HEX_SWIPE_OUT"] else { throw XCTSkip("Run through scripts/swipebench") }
        let first = Int(environment["HEX_SWIPE_FIRST"] ?? "") ?? 0
        let count = Int(environment["HEX_SWIPE_COUNT"] ?? "") ?? .max
        let landscape = environment["HEX_SWIPE_ORIENTATION"] == "landscape"
        let swipes = try Self.load(input)

        let app = XCUIApplication()
        app.launchArguments = ["-HexFocus", "YES", "-HexOrientation", landscape ? "landscape" : "portrait"]
        app.launch()
        let field = app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)

        var frames: [String: CGRect] = [:]
        for key in app.keys.allElementsBoundByIndex where key.frame.width > 0 {
            let name = key.identifier.hasPrefix("hex.") ? String(key.identifier.dropFirst(4)) : key.label.lowercased()
            if name.count == 1, name.first!.isLowercase { frames[name] = key.frame }
        }
        let fit = try XCTUnwrap(Fit(frames: frames, rows: Self.rows, start: Self.rowStart, center: Self.rowCenter), "letter keys: \(frames.keys.sorted())")
        let orientation: UIInterfaceOrientation = landscape ? .landscapeRight : .portrait

        func bar() -> [String] {
            if let snapshot = try? app.otherElements["Typing Predictions"].snapshot() {
                var labels: [String] = []
                func walk(_ node: XCUIElementSnapshot) {
                    if node.elementType == .button { labels.append(node.label) }
                    node.children.forEach(walk)
                }
                walk(snapshot)
                return labels
            }
            return (0..<3).map { app.descendants(matching: .any).matching(identifier: "hex.suggestion.\($0)").firstMatch }.filter(\.exists).map(\.label)
        }
        func text() -> String { field.value as? String ?? "" }
        func clear() {
            let length = text().count
            if length > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: length)) }
        }

        var out = ""
        for (index, (word, points)) in swipes.enumerated() where index >= first && index < first + count {
            clear()
            let start = Date()
            while !text().isEmpty, Date().timeIntervalSince(start) < 2 { Thread.sleep(forTimeInterval: 0.05) }
            let begin = 0.05
            let path = XCPointerEventPath(forTouchAt: fit.point(points[0].x, points[0].y), offset: begin)
            for point in points.dropFirst() { path.move(to: fit.point(point.x, point.y), atOffset: begin + point.t) }
            path.liftUp(atOffset: begin + points.last!.t + 0.02)
            let record = XCSynthesizedEventRecord(name: word, interfaceOrientation: orientation)
            record.add(path)
            try record.synthesize()
            var typed = text()
            var stable = 0
            while stable < 3, Date().timeIntervalSince(start) < 8 {
                Thread.sleep(forTimeInterval: 0.1)
                let now = text()
                stable = now == typed ? stable + 1 : 0
                typed = now
            }
            let typedWord = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            out += "\(index)\t\(word)\t\(typedWord)\t\(bar().joined(separator: "|"))\n"
            if index % 10 == 9 { try out.write(toFile: output, atomically: true, encoding: .utf8) }
        }
        try out.write(toFile: output, atomically: true, encoding: .utf8)
    }
}

private struct Fit {
    let scaleX, offsetX, scaleY, offsetY: Double

    init?(frames: [String: CGRect], rows: [String], start: [Double], center: [Double]) {
        var xs: [(Double, Double)] = [], ys: [(Double, Double)] = []
        for (row, letters) in rows.enumerated() {
            for (column, letter) in letters.enumerated() {
                guard let frame = frames[String(letter)] else { return nil }
                xs.append((start[row] + 0.1 * Double(column), frame.midX))
                ys.append((center[row], frame.midY))
            }
        }
        func line(_ pairs: [(Double, Double)]) -> (Double, Double) {
            let n = Double(pairs.count)
            let sx = pairs.map(\.0).reduce(0, +), sy = pairs.map(\.1).reduce(0, +)
            let sxx = pairs.map { $0.0 * $0.0 }.reduce(0, +), sxy = pairs.map { $0.0 * $0.1 }.reduce(0, +)
            let slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
            return (slope, (sy - slope * sx) / n)
        }
        (scaleX, offsetX) = line(xs)
        (scaleY, offsetY) = line(ys)
    }

    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: scaleX * x + offsetX, y: scaleY * y + offsetY) }
}
