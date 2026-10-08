import Foundation
import KeyboardCore

public enum MemoryStore {
    private static var url: URL {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)
        return (container ?? .applicationSupportDirectory).appending(path: "typing-memory.json")
    }

    static func load() -> TypingMemory {
        (try? JSONDecoder().decode(TypingMemory.self, from: Data(contentsOf: url))) ?? TypingMemory()
    }

    static func save(_ memory: TypingMemory) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(memory).write(to: url, options: .atomic)
    }

    public static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
