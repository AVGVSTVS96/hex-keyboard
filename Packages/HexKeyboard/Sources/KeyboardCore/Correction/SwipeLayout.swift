/// One touch of a swipe: where it was in points, and when, in seconds.
public struct SwipePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var time: Double

    public init(x: Double, y: Double, time: Double) {
        self.x = x
        self.y = y
        self.time = time
    }
}

/// Where the 26 letter keys are, in the unit square the encoder reads a swipe in: the box around the letter keys
/// and their gaps, so QWERTY's keys sit at x = 0.05 … 0.95 and y = 1/6, 1/2 and 5/6. Any keyboard works.
public struct SwipeLayout: Sendable, Equatable {
    let frame: Rect
    let centers: [(x: Double, y: Double)]

    /// `centers` holds a point in the keyboard's own coordinates for each of a–z; `frame` is the box around them all.
    public init?(centers: [Character: (x: Double, y: Double)], frame: Rect) {
        let ordered = (0..<Swipe.letters).compactMap { centers[Character(UnicodeScalar(UInt8(97 + $0)))] }
        guard ordered.count == Swipe.letters, frame.width > 0, frame.height > 0 else { return nil }
        self.frame = frame
        self.centers = ordered.map { (($0.x - frame.x) / frame.width, ($0.y - frame.y) / frame.height) }
    }

    /// The letters of a keyboard as it is laid out now.
    public init?(grid: KeyGrid) {
        var centers: [Character: (x: Double, y: Double)] = [:]
        var box: (minX: Double, minY: Double, maxX: Double, maxY: Double)?
        for (key, frame) in grid.rows.joined() {
            guard let label = key.label?.lowercased(), label.utf8.count == 1, let letter = label.first, letter.isASCII, letter.isLowercase else { continue }
            let cell = grid.cell(of: frame)
            centers[letter] = (frame.midX, frame.midY)
            box = (min(box?.minX ?? cell.x, cell.x), min(box?.minY ?? cell.y, cell.y),
                   max(box?.maxX ?? cell.x + cell.width, cell.x + cell.width), max(box?.maxY ?? cell.y + cell.height, cell.y + cell.height))
        }
        guard let box else { return nil }
        self.init(centers: centers, frame: Rect(x: box.minX, y: box.minY, width: box.maxX - box.minX, height: box.maxY - box.minY))
    }

    public static func == (a: SwipeLayout, b: SwipeLayout) -> Bool {
        a.frame == b.frame && a.centers.elementsEqual(b.centers) { $0.x == $1.x && $0.y == $1.y }
    }

    /// The path as the encoder reads it: x and y in the unit square, resampled
    /// to 60 Hz and then to 64 evenly spaced points by linear interpolation.
    func resampled(_ path: [SwipePoint]) -> (x: [Float], y: [Float]) {
        let start = path[0].time
        let x = path.map { ($0.x - frame.x) / frame.width }
        let y = path.map { ($0.y - frame.y) / frame.height }
        let time = path.map { ($0.time - start) * 1000 }
        var rx = x, ry = y
        if let end = time.last, end > 1e-3 {
            let count = max(2, Int((end / (1000.0 / 60)).rounded(.toNearestOrEven)) + 1)
            let grid = (0..<count).map { end * Double($0) / Double(count - 1) }
            rx = Swipe.interpolate(grid, time, x)
            ry = Swipe.interpolate(grid, time, y)
        }
        let index = (0..<Swipe.inputSteps).map { Double(rx.count - 1) * Double($0) / Double(Swipe.inputSteps - 1) }
        let at = (0..<rx.count).map(Double.init)
        return (Swipe.interpolate(index, at, rx).map(Float.init), Swipe.interpolate(index, at, ry).map(Float.init))
    }
}

extension Swipe {
    /// `values` read at each of the ascending `points`, linearly between the ascending `positions` they are given at.
    static func interpolate(_ points: [Double], _ positions: [Double], _ values: [Double]) -> [Double] {
        var segment = 0
        return points.map { point in
            while segment < positions.count - 2, positions[segment + 1] < point { segment += 1 }
            let (a, b) = (positions[segment], positions[segment + 1])
            guard b > a else { return values[segment] }
            let fraction = min(max((point - a) / (b - a), 0), 1)
            return values[segment] + (values[segment + 1] - values[segment]) * fraction
        }
    }
}
