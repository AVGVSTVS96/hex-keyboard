public struct Rect: Hashable, Sendable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    func distanceSquared(toX px: Double, y py: Double) -> Double {
        let dx = max(x - px, 0, px - (x + width))
        let dy = max(y - py, 0, py - (y + height))
        return dx * dx + dy * dy
    }
}

public struct GridMetrics: Hashable, Sendable {
    public var columns, sideInset, keyGap, rowGap, keyHeight, numberRowHeight, topInset: Double

    public init(columns: Double, sideInset: Double, keyGap: Double, rowGap: Double, keyHeight: Double, numberRowHeight: Double, topInset: Double) {
        self.columns = columns
        self.sideInset = sideInset
        self.keyGap = keyGap
        self.rowGap = rowGap
        self.keyHeight = keyHeight
        self.numberRowHeight = numberRowHeight
        self.topInset = topInset
    }
}

public struct KeyGrid: Sendable {
    public private(set) var rows: [[(key: Key, frame: Rect)]] = []
    private var bands: [ClosedRange<Double>] = []

    public init() {}

    public init(_ layout: KeyboardLayout, width: Double, metrics: GridMetrics) {
        let available = width - metrics.sideInset * 2 + metrics.keyGap
        let pitch = available / metrics.columns
        var y = metrics.topInset
        for (index, row) in layout.rows.enumerated() {
            let height = layout.hasNumberRow && index == 0 ? metrics.numberRowHeight : metrics.keyHeight
            let fixed = row.compactMap(\.width.span).reduce(0, +)
            let fills = row.count { $0.width == .fill }
            let fillSpan = fills > 0 ? max(available / pitch - fixed, 0) / Double(fills) : 0
            var x = metrics.sideInset - metrics.keyGap / 2
            var keys: [(key: Key, frame: Rect)] = []
            for item in row {
                let span = (item.width.span ?? fillSpan) * pitch
                if case .key(let key) = item {
                    keys.append((key, Rect(x: x + metrics.keyGap / 2, y: y, width: span - metrics.keyGap, height: height)))
                }
                x += span
            }
            let top = index == 0 ? -Double.infinity : y - metrics.rowGap / 2
            let bottom = index == layout.rows.count - 1 ? Double.infinity : y + height + metrics.rowGap / 2
            rows.append(keys)
            bands.append(top...bottom)
            y += height + metrics.rowGap
        }
    }

    public func index(atX x: Double, y: Double) -> (row: Int, key: Int)? {
        guard let row = bands.firstIndex(where: { $0.contains(y) }),
              let key = rows[row].indices.min(by: { rows[row][$0].frame.distanceSquared(toX: x, y: y) < rows[row][$1].frame.distanceSquared(toX: x, y: y) })
        else { return nil }
        return (row, key)
    }

    public func key(atX x: Double, y: Double) -> Key? {
        index(atX: x, y: y).map { rows[$0.row][$0.key].key }
    }
}
