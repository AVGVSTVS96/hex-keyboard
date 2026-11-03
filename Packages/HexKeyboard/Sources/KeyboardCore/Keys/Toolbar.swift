/// What sits above the keys (docs/design.md): the bar, with the tools at its left, or a panel's results and search row
/// in its place. The keys' `topInset` is the gap under it. On iPhones the bar is the mic's height, with `gap` above it,
/// below it and beside it (`BarLayout`).
public struct Toolbar: Hashable, Sendable {
    /// Padding above the bar, or above a panel's results.
    public var top: Double
    public var bar: Double
    public var mic: Double
    public var results: Double
    public var field: Double

    public static let fieldGap = 6.0
    /// The space around the mic: to the top of the keyboard's backdrop, to the keys, and to the keyboard's side
    /// where the keys reach it. With it, the keyboard is as tall as Apple's with its suggestions (iPhone Duo, iOS 27.1).
    public static let gap = 7.0
    /// iOS draws the keyboard's backdrop this far above the keyboard's own top (iPhone Duo, iOS 27.1 simulator).
    public static let backdropAbove = 4.0
    /// How much of the bar's bottom goes nowhere, so a reach for the top row never picks a suggestion: with the gap
    /// under the bar, 17 above the keys.
    public static let deadEdge = 10.0
    /// The part of the gap above the keys that belongs to the top row; the rest goes nowhere, so a reach for the top
    /// row never opens a panel.
    public static let keysReach = 5.0

    public init(top: Double, bar: Double, mic: Double, results: Double, field: Double) {
        self.top = top
        self.bar = bar
        self.mic = mic
        self.results = results
        self.field = field
    }

    public var height: Double { top + bar }
    public var panelHeight: Double { top + results + Self.fieldGap + field }
    /// Where height is short, a panel's results are one row.
    public var isCompact: Bool { results < Self.phone.results }

    /// What's above the keys while `panel` is open: with Compact Emoji & GIFs on, those two panels are one row on
    /// every screen.
    public func showing(_ panel: Panel?, compact: Bool) -> Toolbar {
        guard compact, panel == .emoji || panel == .gif else { return self }
        return compacted
    }

    /// A panel in `room`, where iOS gives the keyboard less height than it asks for (the open Duo half folded on its
    /// side): results that don't fit go to one row, which gives up whatever is still missing.
    public func fitting(_ room: Double) -> Toolbar {
        guard panelHeight > room else { return self }
        var toolbar = compacted
        toolbar.results = max(min(toolbar.results, room - top - Self.fieldGap - toolbar.field), 0)
        return toolbar
    }

    private var compacted: Toolbar {
        var toolbar = self
        toolbar.results = min(results, Self.compactResults)
        toolbar.field = min(field, Self.compactField)
        return toolbar
    }

    static let phone = Toolbar(top: gap - backdropAbove, bar: 38, mic: 38, results: 136, field: 40)
    static let compactResults = 46.0
    static let compactField = 34.0

    static func compact(mic: Double) -> Toolbar {
        Toolbar(top: gap - backdropAbove, bar: mic, mic: mic, results: compactResults, field: compactField)
    }

    /// iPad, where iOS draws its own bar above the keyboard.
    static let pad = Toolbar(top: 0, bar: 36, mic: 34, results: compactResults, field: compactField)
}
