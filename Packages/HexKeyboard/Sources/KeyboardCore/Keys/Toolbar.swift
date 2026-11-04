/// What sits above the keys (docs/design.md): the bar, with the tools at its left, or a panel's results and search row
/// in its place. The keys' `topInset` is the gap under it. On iPhones the bar has `gap` above it and below it; the mic, a
/// circle smaller than the bar so it sits in proportion with the tools beside it, is centered in it (`BarLayout`).
public struct Toolbar: Hashable, Sendable {
    /// Padding above the bar, or above a panel's results.
    public var top: Double
    public var bar: Double
    public var mic: Double
    /// The round buttons beside the mic: cancel while you dictate, and turning the microphone off while it's kept on.
    public var pill: Double { mic - 4 }
    public var results: Double
    public var field: Double

    public static let fieldGap = 6.0
    /// The space above the bar, to the top of the keyboard's backdrop, and below it, to the keys. With it, the keyboard is
    /// as tall as Apple's with its suggestions (iPhone Duo, iOS 27.1).
    public static let gap = 7.0
    /// iOS draws the keyboard's backdrop this far above the keyboard's own top (iPhone Duo, iOS 27.1 simulator), and
    /// further on the open Duo in landscape.
    public static let backdropAbove = 4.0
    public static let openWideBackdropAbove = 7.0
    /// How far over the bar's bottom, or a panel's search row, the top row takes taps: with the gap under the bar, a
    /// reach of 17 above the keys types the key reached for, never a suggestion, a tool or a panel's button.
    public static let topRowReach = 10.0

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

    /// A panel in `room`, where iOS gives the keyboard less height than it asks for (the open Duo in portrait, slightly
    /// folded): results that don't fit go to one row, which gives up whatever is still missing. iOS rounds the
    /// keyboard's height to the screen's pixels (419.68 asked on the open Duo in portrait is 419.67 given), so less than
    /// a point short still fits.
    public func fitting(_ room: Double) -> Toolbar {
        guard panelHeight > room + 1 else { return self }
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

    static let phone = Toolbar(top: gap - backdropAbove, bar: 38, mic: 32, results: 136, field: 40)
    static let compactResults = 46.0
    static let compactField = 34.0

    static func compact(bar: Double, backdropAbove: Double = backdropAbove) -> Toolbar {
        Toolbar(top: gap - backdropAbove, bar: bar, mic: bar - 6, results: compactResults, field: compactField)
    }

    /// iPad, where iOS draws its own bar above the keyboard.
    static let pad = Toolbar(top: 0, bar: 36, mic: 30, results: compactResults, field: compactField)
}
