import KeyboardCore
import Foundation
import KeyboardUI

/// How much one device typed and said, a day at a time: the iPhone, from the keyboard's counts and Transcripts, or
/// the Mac, from Keystroke.
struct Activity {
    /// Typing or talking on one day. Speed is `paced` words over `seconds`: for typing, words of five characters a
    /// minute of typing, pauses left out; for talking, the words of each dictation over its length.
    struct Channel {
        var words = 0
        var characters = 0
        var paced = 0.0
        var seconds = 0.0
        var keys = 0
        var deletes = 0
        var dictations = 0
        var corrected = 0
        var undone = 0
        var picked = 0
        var emoji = 0
        /// Characters in each hour of the day, midnight first.
        var hours = [Double](repeating: 0, count: 24)

        static func + (lhs: Self, rhs: Self) -> Self {
            var sum = lhs
            sum.words += rhs.words
            sum.characters += rhs.characters
            sum.paced += rhs.paced
            sum.seconds += rhs.seconds
            sum.keys += rhs.keys
            sum.deletes += rhs.deletes
            sum.dictations += rhs.dictations
            sum.corrected += rhs.corrected
            sum.undone += rhs.undone
            sum.picked += rhs.picked
            sum.emoji += rhs.emoji
            sum.hours = zip(lhs.hours, rhs.hours).map(+)
            return sum
        }

        /// Words a minute, once there's a minute to tell by.
        var speed: Double? { seconds >= 60 ? paced / seconds * 60 : nil }
        var isEmpty: Bool { words == 0 && keys == 0 && dictations == 0 }
    }

    struct Day {
        var typed = Channel()
        var said = Channel()
    }

    enum Kind: Hashable { case typed, said }

    /// Days with something in them, by their start.
    var days: [Date: Day] = [:]
    /// Words by the app they went into, most first.
    var apps: [Kind: [(name: String, words: Int)]] = [:]

    func channel(_ kind: Kind, on day: Date) -> Channel {
        days[day].map { kind == .typed ? $0.typed : $0.said } ?? Channel()
    }

    func total(_ kind: Kind, since start: Date = .distantPast) -> Channel {
        days.filter { $0.key >= start }.values.reduce(Channel()) { $0 + (kind == .typed ? $1.typed : $1.said) }
    }

    func isEmpty(_ kind: Kind) -> Bool { total(kind).isEmpty }

    static func day(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

extension Activity {
    /// The iPhone's: the hours the keyboard shared and every transcript.
    init(hours: [TypingHour], transcripts: [Transcript]) {
        var apps: [String: Int] = [:]
        for hour in hours {
            guard let date = Self.day(hour.day), (0 ..< 24).contains(hour.hour) else { continue }
            let tally = hour.tally
            var channel = Channel(
                words: tally.words, characters: tally.characters, paced: Double(tally.characters) / 5, seconds: hour.seconds, keys: tally.keys,
                deletes: tally.deletes, corrected: tally.corrected, undone: tally.undone, picked: tally.picked, emoji: tally.emoji
            )
            channel.hours[hour.hour] = Double(tally.characters)
            days[date, default: Day()].typed = days[date, default: Day()].typed + channel
            if !hour.app.isEmpty { apps[hour.app, default: 0] += tally.words }
        }
        let calendar = Calendar.current
        var said: [String: Int] = [:]
        for transcript in transcripts where !transcript.text.isEmpty {
            let words = transcript.words
            if transcript.typed, let app = transcript.app { said[app, default: 0] += words }
            var channel = Channel(words: words, characters: transcript.text.count, paced: Double(words), seconds: transcript.seconds, dictations: 1)
            channel.hours[calendar.component(.hour, from: transcript.date)] = Double(transcript.text.count)
            let date = calendar.startOfDay(for: transcript.date)
            days[date, default: Day()].said = days[date, default: Day()].said + channel
        }
        self.apps[.typed] = Self.named(apps)
        self.apps[.said] = Self.named(said)
    }

    private static func named(_ apps: [String: Int]) -> [(name: String, words: Int)] {
        apps.map { (name: AppName.of($0.key), words: $0.value) }.filter { $0.words > 0 }.sorted { $0.words > $1.words }
    }
}
