/// Where the bar's parts go, on every screen from one rule: each button is one circle (`Toolbar.button`) centered in
/// a square cell the bar's height, or a key wide where keys are narrower (never narrower than itself), so it has as much room on its sides as above
/// and below. The cells are set out as the top row's keys are: the More button's and the tools' from the first key's
/// left edge and the mic's ending on the last key's right edge, a key gap apart, so the buttons keep one size and
/// spacing on every screen and the mic sits evenly in its corner. Between them the three suggestions share the bar, or
/// on a phone's bar wide enough take what they need and leave the rest to the word's emoji, beside them rather than in
/// the third one's place. Neither depends on the emoji, so the suggestions never move as you type, as Apple's don't.
/// While you dictate, the cancel button takes the next cell after the tools, and the recording, a capsule the mic grows
/// into, runs from where the next button would be to the mic's right edge, or to the last key's where the mic sits in
/// the bottom row.
public struct BarLayout: Hashable, Sendable {
    public var mic: Rect?
    public var tools: [Rect]
    public var more: Rect?
    /// The suggestions' span.
    public var minX, maxX: Double
    public var cancel: Rect
    public var recording: Rect
    public var slots: [Rect]
    /// The emoji's place: beside the suggestions where the bar has room for them, else the third suggestion's.
    public var emoji: Rect
    public var emojiBeside: Bool
    /// From one button's center to the next one's.
    public var pitch: Double

    /// The gap between the end buttons and the suggestions.
    public static let gap = 4.0
    /// A suggestion never needs more width than a third of an iPhone's bar in portrait.
    public static let slotWidth = 130.0
    public static let emojiPitch = 36.0

    /// `keys` are the top row's keys, left to right, as their edges. Where a suggestion is at most `maximumSlot` wide
    /// (Apple's iPad), the three are centered in their span.
    public init(
        _ toolbar: Toolbar, keys: [(minX: Double, maxX: Double)], tools: Int, more: Bool = false, mic: Bool = true,
        maximumSlot: Double = .infinity
    ) {
        let row = (y: toolbar.top, height: toolbar.bar)
        let side = toolbar.button
        let left = keys.first?.minX ?? 0, right = keys.last?.maxX ?? 0
        let cell = max(min(keys.map { $0.maxX - $0.minX }.min() ?? row.height, row.height), side)
        let pitch = cell + (keys.count > 1 ? keys[1].minX - keys[0].maxX : 0)
        self.pitch = pitch
        let inset = (cell - side) / 2
        func button(at x: Double) -> Rect {
            Rect(x: x + inset, y: row.y + (row.height - side) / 2, width: side, height: side)
        }
        let leading = (0..<((more ? 1 : 0) + tools)).map { button(at: left + Double($0) * pitch) }
        self.more = more ? leading.first : nil
        self.tools = Array(leading.dropFirst(more ? 1 : 0))
        self.mic = mic ? button(at: right - cell) : nil
        minX = leading.last.map { $0.x + $0.width + inset + Self.gap } ?? left
        maxX = self.mic.map { $0.x - inset - Self.gap } ?? right
        cancel = button(at: left + Double(leading.count) * pitch)
        let start = cancel.x + pitch
        recording = Rect(x: start, y: cancel.y, width: (self.mic.map { $0.x + $0.width } ?? right) - start, height: side)
        let span = maxX - minX
        emojiBeside = maximumSlot == .infinity && span - 3 * Self.slotWidth >= 2 * Self.emojiPitch
        let slot = emojiBeside ? Self.slotWidth : min(span / 3, maximumSlot)
        let first = emojiBeside ? minX : minX + (span - 3 * slot) / 2
        slots = (0..<3).map { Rect(x: first + Double($0) * slot, y: row.y, width: slot, height: row.height) }
        let besideX = first + 3 * slot
        self.emoji = emojiBeside ? Rect(x: besideX, y: row.y, width: maxX - besideX, height: row.height) : slots[2]
    }
}
