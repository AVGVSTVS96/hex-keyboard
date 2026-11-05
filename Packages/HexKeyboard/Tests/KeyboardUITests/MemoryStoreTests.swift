import Foundation
import KeyboardCore
import Testing
@testable import KeyboardUI

/// Each store stands for a keyboard view controller; iOS makes a new one in the same process each time the keyboard
/// comes up.
@MainActor
@Suite(.serialized)
struct MemoryStoreTests {
    let url = URL.applicationSupportDirectory.appending(path: "typing-memory.json")

    @Test func savesOnlyOverTheMemoryItRead() async throws {
        try write(words: ["their"])
        let keyboard = MemoryStore()
        keyboard.save(TypingMemory(), sharing: false)
        #expect(try saved() == ["their"], "a keyboard whose read hasn't landed keeps what's saved")

        var memory = try #require(await refresh(keyboard))
        #expect(memory.counts.keys.sorted() == ["their"])
        memory.record("there", after: nil)
        keyboard.save(memory, sharing: false)
        memory.record("they're", after: nil)
        keyboard.save(memory, sharing: false)
        #expect(try saved() == ["their", "there", "they're"], "a keyboard saves over its own saves")

        try write(words: ["other"])
        memory.record("stale", after: nil)
        keyboard.save(memory, sharing: false)
        #expect(try saved() == ["other"], "another app's keyboard saved since, so this one's older memory isn't kept")
        #expect(await refresh(keyboard)?.counts.keys.sorted() == ["other"])
    }

    @Test func aNewKeyboardInTheSameProcessReadsTheFile() async throws {
        try write(words: ["their"])
        #expect(await refresh(MemoryStore())?.counts.keys.sorted() == ["their"])
        #expect(await refresh(MemoryStore())?.counts.keys.sorted() == ["their"], "the next keyboard reads it too")
    }

    @Test func neverSavesOverAFileItCouldNotRead() async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"resets\":0,\"memory\":{\"counts\":".utf8).write(to: url)
        let keyboard = MemoryStore()
        #expect(await refresh(keyboard) == nil)
        keyboard.save(TypingMemory(), sharing: false)
        #expect(try Data(contentsOf: url) == Data("{\"resets\":0,\"memory\":{\"counts\":".utf8))

        try FileManager.default.removeItem(at: url)
        #expect(await refresh(keyboard) == TypingMemory(), "with no file at all, a keyboard starts fresh")
    }

    @Test func aRestoredMemoryOutlastsAReset() async throws {
        SettingsStore.set(7, forKey: "memoryResets")
        defer { SettingsStore.set(0, forKey: "memoryResets") }
        try write(words: ["their"])
        #expect(await refresh(MemoryStore()) == TypingMemory(), "a memory saved before the reset is let go")
        try write(words: ["their"], resets: nil)
        #expect(await refresh(MemoryStore())?.counts.keys.sorted() == ["their"], "one scripts/restore put back is kept")
        SettingsStore.set(8, forKey: "memoryResets")
        #expect(await refresh(MemoryStore()) == TypingMemory(), "and a reset after a keyboard read it lets it go")
    }

    @Test func savesAMemoryHoldingNaN() async throws {
        try write(words: ["their"])
        let keyboard = MemoryStore()
        var memory = try #require(await refresh(keyboard))
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        memory.touches = try decoder.decode(TouchModel.self, from: Data("""
            {"layouts":{"standard":{"m":{"all":{"count":2,"meanX":"nan","meanY":2.5,"scatterXX":0.02,"scatterXY":0,\
            "scatterYY":0.01},"lately":{"count":2,"x":7.5,"y":2.5},"now":{"count":2,"x":7.5,"y":2.5},"weights":[0.3,0.3,0.4]}}}}
            """.utf8))
        memory.record("there", after: nil)
        keyboard.save(memory, sharing: false)
        #expect(try saved() == ["their", "there"], "one NaN doesn't stop the memory from saving")
        let read = try #require(await refresh(MemoryStore()))
        #expect(read.counts.keys.sorted() == ["their", "there"], "and it reads back")
        #expect(read.touches.taps(for: "m", on: .standard) == 0, "with the key that held the NaN started over")
    }

    private func refresh(_ keyboard: MemoryStore) async -> TypingMemory? {
        var memory: TypingMemory?
        keyboard.refresh { memory = $0 }
        await withCheckedContinuation { done in MemoryStore.queue.async { Task { @MainActor in done.resume() } } }
        return memory
    }

    private func write(words: [String], resets: Int? = 0) throws {
        var memory = TypingMemory()
        for word in words { memory.record(word, after: nil) }
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(memory))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var file: [String: Any] = ["memory": saved]
        file["resets"] = resets
        try JSONSerialization.data(withJSONObject: file).write(to: url)
    }

    private func saved() throws -> [String] {
        MemoryStore.queue.sync {}
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return ((saved?["memory"] as? [String: Any])?["counts"] as? [String: Int])?.keys.sorted() ?? []
    }
}
