import Foundation
import Testing
@testable import KeyboardCore

/// Files on the iPhone as builds before this one wrote them. A type that stops reading one loses what it holds: the
/// keyboard won't save over a memory it can't read, so it stops learning, and the other stores start over empty. A
/// field added to one of these types needs a default its decoder fills in (`decodeIfPresent`), and these stay as they are.
struct SavedFormatTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func typingMemoryAsSaved() throws {
        let memory = try decode(TypingMemory.self, """
            {"counts":{"hello":3,"world":2},"kept":["iikb"],"following":{"hello":{"world":2}},"total":5,\
            "spacesAfterSpace":1,"keysAfterSpace":4,"touches":{"layouts":{"standard":{"m":{\
            "all":{"count":2,"meanX":7.5,"meanY":2.5,"scatterXX":0.02,"scatterXY":0,"scatterYY":0.01},\
            "lately":{"count":2,"x":7.5,"y":2.5},"now":{"count":2,"x":7.5,"y":2.5},"weights":[0.3,0.3,0.4]}}},\
            "recent":{"standard":{"m":[{"x":0.1,"y":-0.1}]}}},\
            "apps":{"com.apple.MobileSMS":{"counts":{"hello":1},"following":{},"total":1}}}
            """)
        #expect(memory.count(of: "hello") == 3)
        #expect(memory.count(of: "world", after: "hello").count == 2)
        #expect(memory.isKept("iikb"))
        #expect(memory.touches.taps(for: "m", on: .standard) == 2)
        #expect(memory.apps?["com.apple.MobileSMS"]?.counts["hello"] == 1)
    }

    @Test func typingMemoryBeforeAppsStillLoads() throws {
        let memory = try decode(TypingMemory.self, """
            {"counts":{"hello":1},"kept":[],"following":{},"total":1,"spacesAfterSpace":0,"keysAfterSpace":0,\
            "touches":{"layouts":{}}}
            """)
        #expect(memory.count(of: "hello") == 1)
        #expect(memory.apps == nil)
    }

    @Test func emojiHistoryAsSaved() throws {
        let history = try decode(EmojiHistory.self, """
            {"scores":{"🍕":1.1},"tones":{"👍":"👍🏽"},"weight":1.21,"apps":{"com.apple.MobileSMS":{"🍕":1.1}}}
            """)
        #expect(history.scores["🍕"] == 1.1)
        #expect(history.tones["👍"] == "👍🏽")
    }

    @Test func clipboardHistoryAsSaved() throws {
        let history = try decode(ClipboardHistory.self, """
            {"saved":[{"content":{"text":{"_0":"hi"}},"found":1762000000,"pinned":true},\
            {"content":{"textFile":{"name":"a.txt","preview":"long"}},"found":1762000001,"pinned":false},\
            {"content":{"image":{"_0":"b.png"}},"found":1762000002,"pinned":false}]}
            """)
        #expect(history.items.map(\.content) == [.text("hi"), .image("b.png"), .textFile(name: "a.txt", preview: "long")])
        #expect(history.items.first?.pinned == true)
    }

    @Test func vocabularyAsSaved() throws {
        let vocabulary = try decode(Vocabulary.self, #"{"terms":[{"term":"Tailscale","heardAs":["tail scale"]}]}"#)
        #expect(vocabulary.corrected("I use tail scale") == "I use Tailscale")
    }

    @Test func gifRecentsAsSaved() throws {
        let recents = try decode(GifRecents.self, #"{"slugs":["a","b"],"apps":{"com.apple.MobileSMS":["b"]}}"#)
        #expect(recents.slugs(in: "com.apple.MobileSMS") == ["b", "a"])
        #expect(try decode(GifRecents.self, #"{"slugs":["a"]}"#).slugs == ["a"])
    }

    @Test func typingHourAsSaved() throws {
        let hour = try decode(TypingHour.self, """
            {"day":"2026-11-04","hour":21,"app":"com.apple.MobileSMS","seconds":42.5,"tally":{"keys":120,"characters":118,\
            "deletes":4,"words":22,"corrected":2,"undone":1,"picked":3,"emoji":1}}
            """)
        #expect(hour.tally.words == 22 && hour.seconds == 42.5 && hour.app == "com.apple.MobileSMS")
    }
}
