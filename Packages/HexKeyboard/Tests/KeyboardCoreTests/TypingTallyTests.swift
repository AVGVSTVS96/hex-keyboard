import Testing
@testable import KeyboardCore

struct TypingTallyTests {
    @Test func countsKeysCharactersAndWords() {
        var engine = TypingEngine.correcting()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("hello world ", in: document)
        engine.perform(.delete, in: document)
        #expect(engine.tally.keys == 13)
        #expect(engine.tally.characters == 12)
        #expect(engine.tally.deletes == 1)
        #expect(engine.tally.words == 2)
        #expect(engine.tally.corrected == 0)
    }

    @Test func countsACorrectionAndItsUndoing() throws {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("helo ", in: document)
        #expect(engine.tally.corrected == 1)
        engine.perform(.delete, in: document)
        let revert = try #require(engine.suggestions.first)
        engine.accept(revert, in: document)
        #expect(engine.tally.undone == 1)
        #expect(engine.tally.words == 1)
    }

    @Test func countsAPickedWordAndWhatItAdded() throws {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("hel", in: document)
        let hello = try #require(engine.suggestions.first { $0.text == "hello" })
        engine.accept(hello, in: document)
        #expect(document.text == "so hello ")
        #expect(engine.tally.picked == 1)
        #expect(engine.tally.words == 1)
        #expect(engine.tally.characters == 6)
        #expect(engine.tally.keys == 3)
    }

    @Test func countsAWordLeftAsTyped() {
        var engine = TypingEngine.correcting()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("hello", in: document)
        engine.endSession()
        #expect(engine.tally.words == 1)
    }

    @Test func countsEmoji() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.handle(.emoji("🙂", base: "🙂"), in: document)
        #expect(engine.tally.emoji == 1)
        #expect(engine.tally.keys == 0)
    }

    @Test func leavesThePanelsSearchOut() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.handle(.panel(.emoji), in: document)
        engine.type("cat", in: document)
        #expect(engine.tally == TypingTally())
    }

    @Test func logCountsTimeBetweenChangesButNotPauses() {
        var log = TypingLog()
        var tally = TypingTally()
        for time in [0.0, 0.3, 0.6, 10, 10.2] {
            tally.keys += 1
            log.note(tally, at: time, day: "2026-11-04", hour: 9, app: "com.apple.MobileSMS")
        }
        let hours = log.take()
        #expect(hours.count == 1)
        #expect(hours[0].tally.keys == 5)
        #expect(abs(hours[0].seconds - 0.8) < 1e-9)
    }

    @Test func logSplitsByHourAndAppAndCountsOnFromWhatItTook() {
        var log = TypingLog()
        var tally = TypingTally()
        tally.words = 2
        log.note(tally, at: 0, day: "2026-11-04", hour: 9, app: "a")
        log.note(tally, at: 1, day: "2026-11-04", hour: 9, app: "a")
        tally.words = 3
        log.note(tally, at: 2, day: "2026-11-04", hour: 10, app: "a")
        tally.words = 5
        log.note(tally, at: 3, day: "2026-11-04", hour: 10, app: "b")
        #expect(log.hours.map(\.tally.words) == [2, 1, 2])
        _ = log.take()
        tally.words = 6
        log.note(tally, at: 4, day: "2026-11-04", hour: 10, app: "b")
        #expect(log.hours.map(\.tally.words) == [1])
        #expect(log.hours.map(\.seconds) == [1])
    }
}
