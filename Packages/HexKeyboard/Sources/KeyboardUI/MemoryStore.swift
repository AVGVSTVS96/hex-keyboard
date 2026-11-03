import Foundation
import KeyboardCore
import notify

/// Keeps what the keyboard learns in the extension's own container, since without Full Access it can't write to the
/// App Group. The app resets it by sharing a new reset token through `SettingsStore`; the keyboard starts over when the
/// token it sees differs from the one its memory was saved under.
/// With Full Access the keyboard also shares its touch model through the group, for the app to show.
public enum MemoryStore {
    nonisolated private struct Saved: Codable {
        var resets: Int
        var memory: TypingMemory
    }

    private static let resetsKey = "memoryResets"
    nonisolated private static let touchesChanged = "com.shahidy.hexkeyboard.touches"

    nonisolated private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "typing-memory.json")
    }

    private static var sharedTouchesURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "touches.json")
    }

    private static var resets: Int? { SettingsStore.value(forKey: resetsKey, sharing: false) as? Int }

    /// The saved file's date and the reset token, as this process last read or wrote them. Each app gets a keyboard of
    /// its own, so another one may have saved since.
    @MainActor private static var known: Version?
    nonisolated private struct Version: Equatable {
        var modified: Date?
        var resets: Int?
    }

    /// Reads and writes the file in turn, off the main thread: at 20,000 words each takes a tenth of a second.
    nonisolated private static let queue = DispatchQueue(label: "com.shahidy.hexkeyboard.memory", qos: .userInitiated)

    nonisolated private static var modified: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Hands `use` the saved memory when it isn't the one this process has: on the first appearance, after another
    /// app's keyboard saved, or after the app reset it.
    @MainActor static func refresh(_ use: @escaping @MainActor (TypingMemory) -> Void) {
        let version = Version(modified: modified, resets: resets)
        guard version != known else { return }
        known = version
        let resets = version.resets
        queue.async {
            let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
            let memory = saved.flatMap { $0.resets == resets ?? $0.resets ? $0.memory : nil } ?? TypingMemory()
            Task { @MainActor in use(memory) }
        }
    }

    @MainActor static func save(_ memory: TypingMemory, sharing: Bool) {
        let resets = resets, sharedTouchesURL = sharing ? sharedTouchesURL : nil
        queue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(Saved(resets: resets ?? 0, memory: memory)).write(to: url, options: .atomic)
            let version = Version(modified: modified, resets: resets)
            Task { @MainActor in known = version }
            guard let sharedTouchesURL, (try? JSONEncoder().encode(memory.touches).write(to: sharedTouchesURL, options: .atomic)) != nil else { return }
            notify_post(touchesChanged)
        }
    }

    private static var emojiURL: URL {
        URL.applicationSupportDirectory.appending(path: "emoji-history.json")
    }

    static func loadEmoji() -> EmojiHistory {
        (try? JSONDecoder().decode(EmojiHistory.self, from: Data(contentsOf: emojiURL))) ?? EmojiHistory()
    }

    static func save(_ emoji: EmojiHistory) {
        try? FileManager.default.createDirectory(at: emojiURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(emoji).write(to: emojiURL, options: .atomic)
    }

    public static func reset() {
        SettingsStore.set(Int.random(in: 1 ... .max), forKey: resetsKey)
        if let sharedTouchesURL { try? FileManager.default.removeItem(at: sharedTouchesURL) }
        notify_post(touchesChanged)
    }

    /// Where your taps land, as the keyboard last shared it.
    public static func sharedTouches() -> TouchModel? {
        sharedTouchesURL.flatMap { try? JSONDecoder().decode(TouchModel.self, from: Data(contentsOf: $0)) }
    }

    /// Calls `handler` on the main queue each time the keyboard shares new touches, until the token is cancelled.
    public static func observeTouches(_ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(touchesChanged, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }
}
