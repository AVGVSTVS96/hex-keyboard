/// What typing did, as counts: never a letter of what was typed. The engine only ever adds to its tally, so the
/// difference between two readings is what happened between them.
public struct TypingTally: Codable, Hashable, Sendable {
    /// Taps on keys that typed or deleted.
    public var keys = 0
    /// Characters typing put in the text: each key's, and what a word picked from the bar added.
    public var characters = 0
    public var deletes = 0
    /// Words you finished, by a space, punctuation, a pick from the bar, or leaving them.
    public var words = 0
    /// Words autocorrect changed, and the changes you took back.
    public var corrected = 0
    public var undone = 0
    /// Words picked from the bar: completions, corrections and next words.
    public var picked = 0
    public var emoji = 0

    public init() {}

    public static func - (lhs: Self, rhs: Self) -> Self {
        lhs.combined(with: rhs, by: -)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        lhs.combined(with: rhs, by: +)
    }

    private func combined(with other: Self, by operation: (Int, Int) -> Int) -> Self {
        var result = Self()
        result.keys = operation(keys, other.keys)
        result.characters = operation(characters, other.characters)
        result.deletes = operation(deletes, other.deletes)
        result.words = operation(words, other.words)
        result.corrected = operation(corrected, other.corrected)
        result.undone = operation(undone, other.undone)
        result.picked = operation(picked, other.picked)
        result.emoji = operation(emoji, other.emoji)
        return result
    }
}

/// One hour of typing in one app: what the tally gained and how long you were typing, pauses left out.
public struct TypingHour: Codable, Hashable, Sendable {
    /// The local day, as `2026-11-04`.
    public var day: String
    public var hour: Int
    /// The app's bundle ID, empty when the keyboard couldn't tell.
    public var app: String
    public var tally: TypingTally
    public var seconds: Double

    public init(day: String, hour: Int, app: String, tally: TypingTally = TypingTally(), seconds: Double = 0) {
        self.day = day
        self.hour = hour
        self.app = app
        self.tally = tally
        self.seconds = seconds
    }
}

/// The hours a keyboard typed and hasn't handed on yet, from readings of the engine's tally at the moments it changed.
/// The time between two readings counts as typing unless it's a pause, longer than `pause`, as Keystroke counts it on
/// the Mac.
public struct TypingLog: Sendable {
    public static let pause = 4.0

    public private(set) var hours: [TypingHour] = []
    private var last: (tally: TypingTally, time: Double)?

    public init() {}

    /// Notes the tally at `time` (seconds on any steady clock), in the hour and app it happened in.
    public mutating func note(_ tally: TypingTally, at time: Double, day: String, hour: Int, app: String) {
        let last = self.last ?? (TypingTally(), time)
        guard tally != last.tally else { return }
        self.last = (tally, time)
        let gap = time - last.time
        let index = hours.firstIndex { $0.day == day && $0.hour == hour && $0.app == app } ?? {
            hours.append(TypingHour(day: day, hour: hour, app: app))
            return hours.count - 1
        }()
        hours[index].tally = hours[index].tally + (tally - last.tally)
        if gap > 0, gap <= Self.pause { hours[index].seconds += gap }
    }

    /// The hours noted so far, which the log then forgets, keeping its last reading so the next one counts from it.
    public mutating func take() -> [TypingHour] {
        defer { hours = [] }
        return hours
    }
}
