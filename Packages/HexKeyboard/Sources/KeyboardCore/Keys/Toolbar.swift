/// What sits above the keys (docs/design.md): the bar, with the pill row under it on an upright iPhone, or a panel's
/// results and search row in their place. The keys' `topInset` is the gap under it.
public struct Toolbar: Hashable, Sendable {
    /// Padding above the bar, or above a panel's results.
    public var top: Double
    public var bar: Double
    public var mic: Double
    /// The pill row's height, under the bar; nil where height is short and the tools sit at the bar's left instead.
    public var pills: Double?
    public var results: Double
    public var field: Double

    public static let pillGap = 8.0
    public static let fieldGap = 6.0
    /// How much of a pill's bottom, and of the bar's where there are no pills, goes nowhere.
    public static let deadEdge = 6.0
    /// The part of the gap above the keys that belongs to the top row; the rest goes nowhere, so a reach for the top
    /// row never opens a panel.
    public static let keysReach = 5.0

    public init(top: Double, bar: Double, mic: Double, pills: Double? = nil, results: Double, field: Double) {
        self.top = top
        self.bar = bar
        self.mic = mic
        self.pills = pills
        self.results = results
        self.field = field
    }

    public var height: Double { top + bar + (pills.map { Self.pillGap + $0 } ?? 0) }
    public var panelHeight: Double { top + results + Self.fieldGap + field }

    static let phone = Toolbar(top: 8, bar: 40, mic: 38, pills: 40, results: 136, field: 40)

    static func compact(top: Double, bar: Double, mic: Double) -> Toolbar {
        Toolbar(top: top, bar: bar, mic: mic, results: 46, field: 34)
    }
}
