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

    @Test func pinnedItemsStayOnTopAndNeverAgeOut() {
        var history = ClipboardHistory()
        history.keep(.text("keep me"), at: 0)
        history.setPinned(true, .text("keep me"))
        var dropped: [ClipboardHistory.Item.Content] = []
        for i in 1 ... 52 { dropped += history.keep(.text("\(i)"), at: Double(i)) }
        #expect(history.items.count == 51)
        #expect(history.items.first == .init(content: .text("keep me"), found: 0, pinned: true))
        #expect(history.items[1].content == .text("52"))
        #expect(dropped == [.text("1"), .text("2")], "the oldest unpinned items age out, for the store to delete")

        history.keep(.text("keep me"), at: 60)
        #expect(history.items.first?.pinned == true, "copying a pinned item again keeps it pinned")
        history.setPinned(false, .text("keep me"))
        #expect(history.items.first?.content == .text("keep me"), "unpinned, it's still the newest")
        history.keep(.text("53"), at: 61)
        #expect(history.items.count == 50, "once unpinned it counts toward the 50")
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
