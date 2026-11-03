/// What sits above the keys (docs/design.md): the bar, with the tools at its left, or a panel's results and search row
/// in its place. The keys' `topInset` is the gap under it.
public struct Toolbar: Hashable, Sendable {
    /// Padding above the bar, or above a panel's results.
    public var top: Double
    public var bar: Double
    public var mic: Double
    public var results: Double
    public var field: Double

    public static let fieldGap = 6.0
    /// How much of the bar's bottom goes nowhere, so a reach for the top row never picks a suggestion.
    public static let deadEdge = 6.0
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

    static let phone = Toolbar(top: 8, bar: 40, mic: 38, results: 136, field: 40)

    static func compact(top: Double, bar: Double, mic: Double) -> Toolbar {
        Toolbar(top: top, bar: bar, mic: mic, results: 46, field: 34)
    }
}
