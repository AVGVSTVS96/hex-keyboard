import Foundation
import KeyboardCore
import notify

/// The hours you typed, as counts, one JSON line each, appended each time a keyboard closes or a message goes. iOS can
/// run the keyboard in two apps at once, so each only ever appends, in one write, and none can lose another's. With
/// Full Access the lines go under the App Group's Library for the app's Stats, after any the keyboard kept in its own
/// container while it had none.
///
/// iOS deletes the group's container whenever an install leaves no app claiming the group, so the keyboard also keeps
/// every line it shared in its own container, and puts them back in a group that lost them. Delete Typing Stats leaves a
/// token in the settings, so a keyboard deletes its copy too rather than putting back what you deleted.
public enum TypingStats {
    nonisolated private static let changed = "com.shahidy.hexkeyboard.typing"
    private static let deletedKey = "typingStatsDeleted"
    private static let forgottenKey = "typingStatsForgotten"

    nonisolated private static var ownURL: URL {
        URL.applicationSupportDirectory.appending(path: "typing.jsonl")
    }

    /// Every line this keyboard shared, as the group should hold them.
    nonisolated private static var keptURL: URL {
        URL.applicationSupportDirectory.appending(path: "typing-shared.jsonl")
    }

    nonisolated private static var sharedURL: URL? {
        AppGroup.library?.appending(path: "typing.jsonl")
    }

    /// Appends at once rather than on a queue: iOS suspends a keyboard the moment its app goes away, before queued
    /// work runs, and a few hundred bytes take no time.
    package static func save(_ hours: [TypingHour], sharing: Bool) {
        guard !hours.isEmpty else { return }
        let encoder = JSONEncoder()
        let lines = Data(hours.compactMap { try? encoder.encode($0) + [UInt8(ascii: "\n")] }.joined())
        guard sharing, let sharedURL else {
            append(lines, to: ownURL)
            return
        }
        forgetIfDeleted()
        let manager = FileManager.default
        if !manager.fileExists(atPath: keptURL.path(percentEncoded: false)), let shared = try? Data(contentsOf: sharedURL) {
            create(shared, at: keptURL)
        } else if !manager.fileExists(atPath: sharedURL.path(percentEncoded: false)), let kept = try? Data(contentsOf: keptURL) {
            create(kept, at: sharedURL)
        }
        if let pending = try? Data(contentsOf: ownURL), append(pending, to: sharedURL) {
            append(pending, to: keptURL)
            try? manager.removeItem(at: ownURL)
        }
        if append(lines, to: sharedURL) {
            append(lines, to: keptURL)
            notify_post(changed)
        }
    }

    /// Deletes this keyboard's copy once after each Delete Typing Stats.
    private static func forgetIfDeleted() {
        guard let deleted = SettingsStore.value(forKey: deletedKey, sharing: false) as? Int,
              deleted != UserDefaults.standard.object(forKey: forgottenKey) as? Int
        else { return }
        try? FileManager.default.removeItem(at: keptURL)
        UserDefaults.standard.set(deleted, forKey: forgottenKey)
    }

    /// Writes a file only when there's none, so of two keyboards putting one back only one does.
    nonisolated private static func create(_ data: Data, at url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = open(url.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT | O_EXCL, 0o644)
        guard file >= 0 else { return }
        defer { close(file) }
        _ = data.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
    }

    @discardableResult nonisolated private static func append(_ data: Data, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = open(url.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard file >= 0 else { return false }
        defer { close(file) }
        return data.withUnsafeBytes { write(file, $0.baseAddress, $0.count) } == data.count
    }

    /// Every hour the keyboard has shared, oldest first.
    nonisolated public static func shared() -> [TypingHour] {
        guard let data = sharedURL.flatMap({ try? Data(contentsOf: $0) }) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(TypingHour.self, from: $0) }
    }

    public static func delete() {
        SettingsStore.set(Int.random(in: 1 ... .max), forKey: deletedKey)
        if let sharedURL { try? FileManager.default.removeItem(at: sharedURL) }
        notify_post(changed)
    }

    /// Calls `handler` on the main queue each time a keyboard shares new hours, until the token is cancelled.
    public static func observe(_ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(changed, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }
}
