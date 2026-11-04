import Foundation
import KeyboardCore
import Testing
@testable import KeyboardUI

/// One test, since what the store knows of the file lasts as long as the process, as in a keyboard.
@MainActor
struct MemoryStoreTests {
    let url = URL.applicationSupportDirectory.appending(path: "typing-memory.json")

    @Test func savesOnlyOverTheMemoryItRead() async throws {
        try write(words: ["their"])
        MemoryStore.save(TypingMemory(), sharing: false)
        #expect(try saved() == ["their"], "a keyboard whose read hasn't landed keeps what's saved")

        var memory = try #require(await refresh())
        #expect(memory.counts.keys.sorted() == ["their"])
        memory.record("there", after: nil)
        MemoryStore.save(memory, sharing: false)
        memory.record("they're", after: nil)
        MemoryStore.save(memory, sharing: false)
        #expect(try saved() == ["their", "there", "they're"], "a keyboard saves over its own saves")

        try write(words: ["other"])
        memory.record("stale", after: nil)
        MemoryStore.save(memory, sharing: false)
        #expect(try saved() == ["other"], "another app's keyboard saved since, so this one's older memory isn't kept")
        #expect(await refresh()?.counts.keys.sorted() == ["other"])
    }

    private func refresh() async -> TypingMemory? {
        var memory: TypingMemory?
        MemoryStore.refresh { memory = $0 }
        await withCheckedContinuation { done in MemoryStore.queue.async { Task { @MainActor in done.resume() } } }
        return memory
    }

    private func write(words: [String]) throws {
        var memory = TypingMemory()
        for word in words { memory.record(word, after: nil) }
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(memory))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["resets": 0, "memory": saved]).write(to: url)
    }

    private func saved() throws -> [String] {
        MemoryStore.queue.sync {}
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return ((saved?["memory"] as? [String: Any])?["counts"] as? [String: Int])?.keys.sorted() ?? []
    }
}
