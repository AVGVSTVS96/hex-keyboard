import Foundation

/// Keystroke's counts of a computer's typing and dictation (never what's typed), the shape every computer shares
/// (docs/computers.md).
enum KeystrokeStats {
    /// Keystroke's file, version 3: each day's `typed` (physical keys) and `voice` (dictation) counts, and the apps
    /// dictation went into. Fields it adds later are left alone.
    private struct Keystroke: Decodable {
        struct Channel: Decodable {
            var keystrokes = 0.0, chars = 0.0, words = 0.0, backspaces = 0.0, activeMs = 0.0, timedChars = 0.0, timedMs = 0.0, inserts = 0.0
            var hourChars: [Double] = []
            var peakWpm = 0.0
        }

        struct Day: Decodable {
            var typed: Channel
            var voice: Channel
        }

        struct App: Decodable {
            var name: String
            var words: Double
        }

        var days: [String: Day]
        var sources: [String: App]?
        var wpmHistogram: [String: Double]?
    }

    static func decode(_ data: Data) -> Activity? {
        guard let file = try? JSONDecoder().decode(Keystroke.self, from: data) else { return nil }
        var activity = Activity()
        for (key, day) in file.days {
            guard let date = Activity.day(key) else { continue }
            activity.days[date] = Activity.Day(typed: typed(day.typed), said: said(day.voice))
        }
        activity.speeds = Dictionary((file.wpmHistogram ?? [:]).compactMap { key, count in Int(key).map { ($0, count) } }, uniquingKeysWith: +)
        activity.apps[.said] = (file.sources ?? [:]).values.map { (name: $0.name, words: Int($0.words)) }.filter { $0.words > 0 }.sorted { $0.words > $1.words }
        return activity
    }

    private static func typed(_ channel: Keystroke.Channel) -> Activity.Channel {
        var typed = Activity.Channel(
            words: Int(channel.words), characters: Int(channel.chars), paced: channel.chars / 5, seconds: channel.activeMs / 1000,
            keys: Int(channel.keystrokes), deletes: Int(channel.backspaces)
        )
        typed.hours = hours(channel.hourChars)
        typed.peak = channel.peakWpm
        return typed
    }

    /// Keystroke knows how long you talked only for some dictations, so the pace goes by those alone.
    private static func said(_ channel: Keystroke.Channel) -> Activity.Channel {
        var said = Activity.Channel(
            words: Int(channel.words), characters: Int(channel.chars), paced: channel.timedChars / 5, seconds: channel.timedMs / 1000,
            dictations: Int(channel.inserts)
        )
        said.hours = hours(channel.hourChars)
        return said
    }

    private static func hours(_ values: [Double]) -> [Double] {
        (0 ..< 24).map { $0 < values.count ? values[$0] : 0 }
    }
}
