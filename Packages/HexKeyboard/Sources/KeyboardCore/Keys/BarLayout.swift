/// Where the bar's parts go, on every screen from the same rule: the mic is as far from the keyboard's side as it is
/// from the keys below it, or in line with the keys where they sit further in, so it never crowds the keyboard's
/// corner. The tools mirror it at the left, round cells the mic's size, after the More button, half as wide, at the far
/// left. Between them the three suggestions share the bar, or on a phone's bar wide enough take what they need and
/// leave the rest to the word's emoji, beside them rather than in the third one's place. Neither depends on the emoji,
/// so the suggestions never move as you type, as Apple's don't.
public struct BarLayout: Hashable, Sendable {
    public var mic: Rect
    public var tools: [Rect]
    public var more: Rect?
    /// The suggestions' and the waveform's span.
    public var minX, maxX: Double
    public var slots: [Rect]
    /// The emoji's place: beside the suggestions where the bar has room for them, else the third suggestion's.
    public var emoji: Rect
    public var emojiBeside: Bool

    /// The gap between neighboring tools, and between the end cells and the suggestions.
    public static let gap = 4.0
    /// A suggestion never needs more width than a third of an iPhone's bar in portrait.
    public static let slotWidth = 130.0
    public static let emojiPitch = 36.0

    /// `width` is the keyboard's window, `screenInset` how far the screen (and the keyboard's backdrop) reaches past
    /// each of its sides, `block` the keys' edges, `topInset` the gap from the bar to the keys. Where a suggestion is
    /// at most `maximumSlot` wide (Apple's iPad), the three are centered in their span.
    public init(
        _ toolbar: Toolbar, width: Double, screenInset: Double, block: (minX: Double, maxX: Double), topInset: Double,
        tools: Int, more: Bool = false, maximumSlot: Double = .infinity
    ) {
        let side = toolbar.mic
        let y = toolbar.top + (toolbar.bar - side) / 2
        let reach = (toolbar.bar - side) / 2 + topInset
        let left = max(block.minX, reach - screenInset)
        let right = min(block.maxX, width + screenInset - reach)
        mic = Rect(x: right - side, y: y, width: side, height: side)
        self.more = more ? Rect(x: left, y: y, width: side / 2, height: side) : nil
        let start = self.more.map { $0.x + $0.width + Self.gap } ?? left
        self.tools = (0..<tools).map { Rect(x: start + Double($0) * (side + Self.gap), y: y, width: side, height: side) }
        minX = self.tools.last.map { $0.x + $0.width + Self.gap } ?? start
        maxX = mic.x - Self.gap
        let span = maxX - minX
        emojiBeside = maximumSlot == .infinity && span - 3 * Self.slotWidth >= 2 * Self.emojiPitch
        let slot = emojiBeside ? Self.slotWidth : min(span / 3, maximumSlot)
        let first = emojiBeside ? minX : minX + (span - 3 * slot) / 2
        let row = (y: toolbar.top, height: toolbar.bar)
        slots = (0..<3).map { Rect(x: first + Double($0) * slot, y: row.y, width: slot, height: row.height) }
        let besideX = first + 3 * slot
        self.emoji = emojiBeside ? Rect(x: besideX, y: row.y, width: maxX - besideX, height: row.height) : slots[2]
    }
}
