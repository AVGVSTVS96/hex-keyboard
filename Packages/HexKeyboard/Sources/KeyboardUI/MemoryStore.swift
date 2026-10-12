import Foundation
import KeyboardCore

/// Keeps what the keyboard learns in the extension's own container, since without Full Access it can't write to the
/// App Group. The app resets it by bumping a counter in the group's defaults; the keyboard starts over when it moved.
public enum MemoryStore {
    private struct Saved: Codable {
        var resets: Int
        var memory: TypingMemory
    }

    private static let resetsKey = "memoryResets"

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "typing-memory.json")
    }

    private static var resets: Int { SettingsStore.defaults.integer(forKey: resetsKey) }

    static func load() -> TypingMemory {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: url)), saved.resets == resets else { return TypingMemory() }
        return saved.memory
    }

    static func save(_ memory: TypingMemory) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Saved(resets: resets, memory: memory)).write(to: url, options: .atomic)
    }

    public static func reset() {
        SettingsStore.defaults.set(resets + 1, forKey: resetsKey)
    }
}
