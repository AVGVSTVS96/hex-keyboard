import Testing
@testable import KeyboardCore

struct SpacingTests {
    private let screens: [(Size, Double)] = Duo.Screen.allCases.map { ($0.size, $0.keyboardWidth) } + [
        (Size(width: 402, height: 874), 402), (Size(width: 874, height: 402), 874), (Size(width: 834, height: 1194), 834),
    ]

    private func keys(_ spacing: KeySpacing, screen: Size, window: Double, numberRow: Bool = false) -> (grid: KeyGrid, height: Double) {
        var settings = KeyboardSettings()
        settings.keySpacing = spacing
        settings.numberRow = numberRow
        let device = DeviceClass(isPad: screen.width == 834, shortSide: min(screen.width, screen.height))
        let context = LayoutContext(device: device, layer: .letters, showsGlobe: true, screen: screen, settings: settings)
        let layout = Layouts.layout(for: context)
        let metrics = KeyboardMetrics.for(context, screen: screen, window: window, style: .ios27)
        return (KeyGrid(layout, width: window, metrics: metrics.grid), metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow))
    }

    private func outline(_ grid: KeyGrid) -> Rect {
        let frames = grid.rows.joined().map(\.frame)
        let minX = frames.map(\.x).min()!, minY = frames.map(\.y).min()!
        return Rect(x: minX, y: minY, width: frames.map { $0.x + $0.width }.max()! - minX, height: frames.map { $0.y + $0.height }.max()! - minY)
    }

    @Test func theKeyboardAndItsOuterEdgesStayWhileTheKeycapsTakeTheGaps() {
        for (screen, window) in screens {
            for numberRow in [false, true] {
                let standard = keys(.standard, screen: screen, window: window, numberRow: numberRow)
                let q = standard.grid.frame(of: "q")!
                for spacing in KeySpacing.allCases where spacing != .standard {
                    let spaced = keys(spacing, screen: screen, window: window, numberRow: numberRow)
                    #expect(abs(spaced.height - standard.height) < 1e-9, "\(spacing) keeps the keyboard's height on \(screen)")
                    let outer = outline(spaced.grid), was = outline(standard.grid)
                    #expect(abs(outer.x - was.x) < 1e-9 && abs(outer.y - was.y) < 1e-9 && abs(outer.width - was.width) < 1e-9 && abs(outer.height - was.height) < 1e-9)
                    let key = spaced.grid.frame(of: "q")!
                    let bigger = spacing.share < 1
                    #expect(bigger ? key.width > q.width && key.height > q.height : key.width < q.width && key.height < q.height, "\(spacing) on \(screen)")
                }
            }
        }
    }

    @Test func theGapsAreAShareOfStandardsWithStandardInTheMiddle() {
        #expect(KeySpacing.allCases.count == 5 && KeySpacing.allCases[KeySpacing.allCases.count / 2] == .standard)
        #expect(KeySpacing.standard.share == 1)
        let metrics = KeyboardMetrics.for(.phone, width: 402, height: 874)
        let tighter = metrics.spaced(.tighter, rows: 4), roomier = metrics.spaced(.roomier, rows: 4)
        #expect(tighter.keyGap == metrics.keyGap / 2 && tighter.rowGap == metrics.rowGap / 2)
        #expect(roomier.keyGap == metrics.keyGap * 3 / 2 && roomier.rowGap == metrics.rowGap * 3 / 2)
        #expect(roomier.keyHeight > 30, "the roomiest keys stay big enough to hit")
    }
}
