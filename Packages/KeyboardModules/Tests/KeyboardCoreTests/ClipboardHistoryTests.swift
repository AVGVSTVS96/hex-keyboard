import Testing
@testable import KeyboardCore

struct ClipboardHistoryTests {
    @Test func newestFirstAndACopyOfTheSameThingMovesUpInsteadOfRepeating() {
        var history = ClipboardHistory()
        history.keep(.text("a"), at: 1)
        history.keep(.text("b"), at: 2)
        history.keep(.text("a"), at: 3)
        #expect(history.items.map(\.content) == [.text("a"), .text("b")])
        #expect(history.items.first?.found == 3)
    }

    @Test func largeCopiesAreKept() {
        var history = ClipboardHistory()
        let log = String(repeating: "x", count: 10_000_000)
        history.keep(.text(log), at: 1)
        #expect(history.items.count == 1)
        history.keep(.text(String(repeating: "y", count: 50_000)), at: 2)
        #expect(history.items.count == 2)
    }

    @Test func clearingKeepsWhatsPinned() {
        var history = ClipboardHistory()
        history.keep(.text("address"), at: 1)
        history.keep(.image("a.png"), at: 2)
        history.keep(.text("code"), at: 3)
        history.setPinned(true, .text("address"))
        #expect(Set(history.removeUnpinned()) == [.image("a.png"), .text("code")])
        #expect(history.items.map(\.content) == [.text("address")])
    }

    @Test func itemsKeptElsewhereJoinWithoutRepeating() {
        var history = ClipboardHistory()
        history.keep(.text("new"), at: 5)
        history.add([.init(content: .text("old"), found: 1, pinned: true), .init(content: .text("new"), found: 2)])
        #expect(history.items.map(\.content) == [.text("old"), .text("new")])
        #expect(history.items.last?.found == 5)
    }

    @Test func nothingAgesOutAndPinnedItemsStayOnTop() {
        var history = ClipboardHistory()
        history.keep(.text("keep me"), at: 0)
        history.setPinned(true, .text("keep me"))
        for i in 1 ... 500 { history.keep(.text("\(i)"), at: Double(i)) }
        #expect(history.items.count == 501, "everything you copied stays until you delete it")
        #expect(history.items.first == .init(content: .text("keep me"), found: 0, pinned: true))
        #expect(history.items[1].content == .text("500"))
        #expect(history.items.last?.content == .text("1"))

        history.keep(.text("keep me"), at: 600)
        #expect(history.items.first?.pinned == true, "copying a pinned item again keeps it pinned")
        history.setPinned(false, .text("keep me"))
        #expect(history.items.first?.content == .text("keep me"), "unpinned, it's still the newest")
        history.remove(.text("keep me"))
        #expect(!history.items.contains { $0.content == .text("keep me") })
    }

    @Test func searchFindsTextInsideItemsIgnoringCase() {
        var history = ClipboardHistory()
        history.keep(.text("Meet at Blue Bottle"), at: 1)
        history.keep(.image("abc"), at: 2)
        history.keep(.text("blueprint.pdf"), at: 3)
        #expect(history.matching("BLUE").map(\.content) == [.text("blueprint.pdf"), .text("Meet at Blue Bottle")])
        #expect(history.matching("").count == 3)
        #expect(history.matching("abc").isEmpty, "images aren't searched by their file name")
    }

    @Test func rowsSayHowLongAgo() {
        let now = 1_000_000_000.0
        #expect(ClipboardHistory.age(of: now - 20, now: now) == "now")
        #expect(ClipboardHistory.age(of: now - 5 * 60, now: now) == "5m")
        #expect(ClipboardHistory.age(of: now - 3 * 3600 - 59, now: now) == "3h")
        #expect(ClipboardHistory.age(of: now - 2 * 86400, now: now) == "2d")
        #expect(ClipboardHistory.age(of: now - 15 * 86400, now: now) == "2w")
        #expect(ClipboardHistory.age(of: now - 400 * 86400, now: now) == "1y")
        #expect(ClipboardHistory.age(of: now + 30, now: now) == "now", "a clock set back shows now")
    }
}

struct ClipboardPasteTests {
    @Test func aPickFromTheClipboardPanelGoesIntoTheAppWholeWhileTheSearchKeepsTheKeys() {
        var engine = TypingEngine()
        let document = TestDocument("see you at ")
        engine.handle(.panel(.clipboard), in: document)
        engine.type("ferry", in: document)
        engine.handle(.paste("1 Ferry Building, San Francisco"), in: document)
        #expect(document.text == "see you at 1 Ferry Building, San Francisco")
        #expect(engine.panel == .clipboard, "the panel stays open, so you can add more")
        #expect(engine.query == "ferry")
    }
}
