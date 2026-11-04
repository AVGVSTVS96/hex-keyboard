/// Where the bar's parts go, on every screen from one rule: they sit on the top row's keys. The More button and the
/// tools are centered over the first keys, each a key wide (up to a bit more than the bar is tall, where keys are
/// wide), so they're the same size, as far apart as the keys and in line with them, and the mic is a circle over the
/// last key. Between them the three suggestions share the bar, or on a phone's bar wide enough take what they need and
/// leave the rest to the word's emoji, beside them rather than in the third one's place. Neither depends on the emoji,
/// so the suggestions never move as you type, as Apple's don't. While you dictate, the recording, a capsule the mic
/// grows into, spans from the key after the tools' next to the mic's edge, or to the last key's where the mic sits in
/// the bottom row, and the cancel button, a circle the mic's size, sits over the key between.
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

    /// The gap between the end cells and the suggestions.
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
        let keys = keys.isEmpty ? [(minX: 0.0, maxX: 0.0)] : keys
        func key(_ index: Int) -> (minX: Double, maxX: Double) { keys[min(max(index, 0), keys.count - 1)] }
        func center(_ index: Int) -> Double { (key(index).minX + key(index).maxX) / 2 }
        func cell(_ index: Int) -> Rect {
            let width = min(key(index).maxX - key(index).minX, row.height * 1.25)
            return Rect(x: center(index) - width / 2, y: row.y, width: width, height: row.height)
        }
        func round(_ side: Double, over index: Int) -> Rect {
            Rect(x: center(index) - side / 2, y: row.y + (row.height - side) / 2, width: side, height: side)
        }
        self.more = more ? cell(0) : nil
        let first = more ? 1 : 0
        self.tools = (0..<tools).map { cell(first + $0) }
        let used = first + tools
        let last = keys.count - 1
        self.mic = mic ? round(toolbar.mic, over: last) : nil
        let lastCell = (self.tools.last ?? self.more).map { $0.x + $0.width }
        minX = lastCell.map { $0 + Self.gap } ?? key(0).minX
        maxX = self.mic.map { $0.x - Self.gap } ?? key(last).maxX
        cancel = round(toolbar.mic, over: used)
        let height = toolbar.mic
        recording = Rect(
            x: key(used + 1).minX, y: row.y + (row.height - height) / 2,
            width: (self.mic.map { $0.x + $0.width } ?? key(last).maxX) - key(used + 1).minX, height: height
        )
        let span = maxX - minX
        emojiBeside = maximumSlot == .infinity && span - 3 * Self.slotWidth >= 2 * Self.emojiPitch
        let slot = emojiBeside ? Self.slotWidth : min(span / 3, maximumSlot)
        let start = emojiBeside ? minX : minX + (span - 3 * slot) / 2
        slots = (0..<3).map { Rect(x: start + Double($0) * slot, y: row.y, width: slot, height: row.height) }
        let besideX = start + 3 * slot
        self.emoji = emojiBeside ? Rect(x: besideX, y: row.y, width: maxX - besideX, height: row.height) : slots[2]
    }
}
