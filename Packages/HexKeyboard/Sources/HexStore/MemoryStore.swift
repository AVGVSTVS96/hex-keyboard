import Foundation
import KeyboardCore
import notify
import os

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
    nonisolated private static let log = Logger(subsystem: "com.shahidy.hexkeyboard", category: "memory")

    nonisolated private static let file = StoredFile<Saved>(URL.applicationSupportDirectory.appending(path: "typing-memory.json"))

    private static var touches: StoredFile<TouchModel>? {
        AppGroup.library.map { StoredFile($0.appending(path: "touches.json")) }
    }

    private static var resets: Int? { SettingsStore.value(forKey: resetsKey, sharing: false) as? Int }

    /// The saved file's date and the reset token. Each app gets a keyboard of its own, so another one may have saved
    /// since this one read, and a keyboard saves only over the version its memory was read from or its own last save:
    /// saving over anything else would wipe what the other learned, or everything when its read hasn't landed yet.
    nonisolated private struct Version: Equatable {
        var modified: Date?
        var resets: Int?
    }

    package init() {}

    /// The version this keyboard's memory was read from; none until its first read lands, or while the file can't be read.
    private var base: Version?
    /// The version this keyboard last saved, kept on `queue`.
    nonisolated(unsafe) private var written: Version?

    /// Reads and writes the file in turn, off the main thread: at 20,000 words each takes a tenth of a second.
    nonisolated package static let queue = DispatchQueue(label: "com.shahidy.hexkeyboard.memory", qos: .userInitiated)

    /// Read from the file system each time: a URL caches its resource values, and `file.url` lives as long as the process.
    nonisolated private static var modified: Date? {
        try? FileManager.default.attributesOfItem(atPath: file.url.path(percentEncoded: false))[.modificationDate] as? Date
    }

    /// Hands `use` the saved memory when it isn't the one this keyboard has: on its first appearance, after another
    /// app's keyboard saved, or after the app reset it. A file that's there but can't be read is never handed over.
    package func refresh(_ use: @escaping @MainActor (TypingMemory) -> Void) {
        let base = base, resets = Self.resets
        Self.queue.async { [self] in
            var version = Version(modified: Self.modified, resets: resets)
            guard version != base, version != written else { return }
            var memory = TypingMemory()
            if version.modified != nil {
                guard case .value(var saved) = Self.file.read() else { return }
                // A restored memory takes the token at once, so a reset made after this read lets it go.
                if saved.resets == nil {
                    saved.resets = resets ?? 0
                    if Self.file.save(saved) {
                        version = Version(modified: Self.modified, resets: resets)
                        written = version
                    }
                }
                if saved.resets == resets ?? saved.resets { memory = saved.memory }
            }
            let touches = memory.touches.finite()
            if touches != memory.touches {
                Self.log.fault("touch model keys holding a NaN or infinity start over")
                memory.touches = touches
            }
            Task { @MainActor [version, memory] in
                self.base = version
                use(memory)
            }
        }
    }

    package func save(_ memory: TypingMemory, sharing: Bool) {
        guard let base else { return }
        let resets = Self.resets, touches = sharing ? Self.touches : nil
        Self.queue.async { [self] in
            let current = Version(modified: Self.modified, resets: resets)
            guard current == base || current == written else { return }
            Self.file.save(Saved(resets: resets ?? 0, memory: memory))
            written = Version(modified: Self.modified, resets: resets)
            guard let touches, touches.save(memory.touches) else { return }
            notify_post(Self.touchesChanged)
        }
    }

    private static let emoji = StoredFile<EmojiHistory>(URL.applicationSupportDirectory.appending(path: "emoji-history.json"))

    package static func loadEmoji() -> EmojiHistory {
        emoji.read().value ?? EmojiHistory()
    }

    package static func save(_ emoji: EmojiHistory) {
        Self.emoji.save(emoji)
    }

    public static func reset() {
        SettingsStore.set(Int.random(in: 1 ... .max), forKey: resetsKey)
        touches?.remove()
        PersonalNetwork.forget()
        notify_post(touchesChanged)
    }

    /// Where your taps land, as the keyboard last shared it.
    public static func sharedTouches() -> TouchModel? {
        touches?.read().value?.finite()
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
