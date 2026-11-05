import Foundation
import KeyboardStore
import Observation

/// Your Mac's typing and dictation as Keystroke (a Mac app that counts both, never what's typed) keeps them in its
/// `typing-stats.json`, which the Mac sends to the backup server each time Keystroke saves it (docs/stats.md). Read
/// again each time Stats comes forward, and the last copy kept, so the Mac shows as it last was while it's asleep or the
/// server is out of reach.
@MainActor @Observable final class MacStats {
    static let shared = MacStats()

    private(set) var activity: Activity?
    /// When Keystroke last saved the copy shown.
    private(set) var asOf: Date?
    @ObservationIgnored private var reading = false

    private static let name = "mac/typing-stats.json"
    private static let copy = URL.cachesDirectory.appending(path: "mac-stats.json")

    private init() {
        activity = (try? Data(contentsOf: Self.copy)).flatMap(Self.decode) // file: cache of the Mac's stats, fetched again from the server
        asOf = try? Self.copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func read() async {
        guard !reading else { return }
        reading = true
        defer { reading = false }
        guard let (data, modified) = await Backup.read(Self.name), modified != asOf, let activity = Self.decode(data) else { return }
        self.activity = activity
        asOf = modified
        try? FileManager.default.createDirectory(at: Self.copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.copy, options: .atomic) // file: cache of the Mac's stats, fetched again from the server
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: Self.copy.path(percentEncoded: false))
    }

    /// Keystroke's file, version 3: each day's `typed` (physical keys) and `voice` (dictation) counts, and the apps
    /// dictation went into. Fields it adds later are left alone.
    private struct Keystroke: Decodable {
        struct Channel: Decodable {
            var keystrokes = 0.0, chars = 0.0, words = 0.0, backspaces = 0.0, activeMs = 0.0, timedChars = 0.0, timedMs = 0.0, inserts = 0.0
            var hourChars: [Double] = []
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
    }

    static func decode(_ data: Data) -> Activity? {
        guard let file = try? JSONDecoder().decode(Keystroke.self, from: data) else { return nil }
        var activity = Activity()
        for (key, day) in file.days {
            guard let date = Activity.day(key) else { continue }
            activity.days[date] = Activity.Day(typed: typed(day.typed), said: said(day.voice))
        }
        activity.apps[.said] = (file.sources ?? [:]).values.map { (name: $0.name, words: Int($0.words)) }.filter { $0.words > 0 }.sorted { $0.words > $1.words }
        return activity
    }

    private static func typed(_ channel: Keystroke.Channel) -> Activity.Channel {
        var typed = Activity.Channel(
            words: Int(channel.words), characters: Int(channel.chars), paced: channel.chars / 5, seconds: channel.activeMs / 1000,
            keys: Int(channel.keystrokes), deletes: Int(channel.backspaces)
        )
        typed.hours = hours(channel.hourChars)
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
