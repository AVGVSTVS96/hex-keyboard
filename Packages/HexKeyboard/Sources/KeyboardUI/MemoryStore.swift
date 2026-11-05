import Foundation
import KeyboardCore
import notify

/// Keeps what the keyboard learns in the extension's own container, since without Full Access it can't write to the
/// App Group. The app resets it by sharing a new reset token through `SettingsStore`; the keyboard starts over when the
/// token it sees differs from the one its memory was saved under.
/// With Full Access the keyboard also shares its touch model through the group, for the app to show.
///
/// Each keyboard view controller has a store of its own, since what it knows of the file belongs with the memory it
/// holds: iOS makes a new controller each time the keyboard comes up, often in a process whose last one read the file.
public final class MemoryStore {
    nonisolated private struct Saved: Codable {
        /// None in a memory `scripts/restore` put back, which is kept under whichever token there is now, so a restore
        /// undoes a reset.
        var resets: Int?
        var memory: TypingMemory
    }

    private static let resetsKey = "memoryResets"
    nonisolated private static let touchesChanged = "com.shahidy.hexkeyboard.touches"

    nonisolated private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "typing-memory.json")
    }

    /// Under the group's Library, where the keyboard's other files are, since a keyboard can't write the group's root.
    private static var sharedTouchesURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "Library/touches.json")
    }

    private static var resets: Int? { SettingsStore.value(forKey: resetsKey, sharing: false) as? Int }

    /// The saved file's date and the reset token. Each app gets a keyboard of its own, so another one may have saved
    /// since this one read, and a keyboard saves only over the version its memory was read from or its own last save:
    /// saving over anything else would wipe what the other learned, or everything when its read hasn't landed yet.
    nonisolated private struct Version: Equatable {
        var modified: Date?
        var resets: Int?
    }

    /// The version this keyboard's memory was read from; none until its first read lands, or while the file can't be read.
    private var base: Version?
    /// The version this keyboard last saved, kept on `queue`.
    nonisolated(unsafe) private var written: Version?

    /// Reads and writes the file in turn, off the main thread: at 20,000 words each takes a tenth of a second.
    nonisolated static let queue = DispatchQueue(label: "com.shahidy.hexkeyboard.memory", qos: .userInitiated)

    nonisolated private static var modified: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Hands `use` the saved memory when it isn't the one this keyboard has: on its first appearance, after another
    /// app's keyboard saved, or after the app reset it. A file that's there but can't be read is never handed over.
    func refresh(_ use: @escaping @MainActor (TypingMemory) -> Void) {
        let base = base, resets = Self.resets
        Self.queue.async { [self] in
            let version = Version(modified: Self.modified, resets: resets)
            guard version != base, version != written else { return }
            var memory = TypingMemory()
            if version.modified != nil {
                guard let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: Self.url)) else { return }
                if saved.resets == nil || saved.resets == resets ?? saved.resets { memory = saved.memory }
            }
            Task { @MainActor in
                self.base = version
                use(memory)
            }
        }
    }

    func save(_ memory: TypingMemory, sharing: Bool) {
        guard let base else { return }
        let resets = Self.resets, sharedTouchesURL = sharing ? Self.sharedTouchesURL : nil
        Self.queue.async { [self] in
            let url = Self.url, current = Version(modified: Self.modified, resets: resets)
            guard current == base || current == written else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(Saved(resets: resets ?? 0, memory: memory)).write(to: url, options: .atomic)
            written = Version(modified: Self.modified, resets: resets)
            guard let sharedTouchesURL else { return }
            try? FileManager.default.createDirectory(at: sharedTouchesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? JSONEncoder().encode(memory.touches).write(to: sharedTouchesURL, options: .atomic)) != nil else { return }
            notify_post(Self.touchesChanged)
        }
    }

    private static var emojiURL: URL {
        URL.applicationSupportDirectory.appending(path: "emoji-history.json")
    }

    static func loadEmoji() -> EmojiHistory {
        (try? JSONDecoder().decode(EmojiHistory.self, from: Data(contentsOf: emojiURL))) ?? EmojiHistory()
    }

    /// Never over a history that's there but can't be read, which `loadEmoji` handed over as empty.
    static func save(_ emoji: EmojiHistory) {
        if FileManager.default.fileExists(atPath: emojiURL.path(percentEncoded: false)),
           (try? JSONDecoder().decode(EmojiHistory.self, from: Data(contentsOf: emojiURL))) == nil { return }
        try? FileManager.default.createDirectory(at: emojiURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(emoji).write(to: emojiURL, options: .atomic)
    }

    public static func reset() {
        SettingsStore.set(Int.random(in: 1 ... .max), forKey: resetsKey)
        if let sharedTouchesURL { try? FileManager.default.removeItem(at: sharedTouchesURL) }
        PersonalNetwork.forget()
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
