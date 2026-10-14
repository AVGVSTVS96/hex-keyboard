import Testing
@testable import KeyboardCore

struct SourceFeedTests {
    private func update(_ before: String, by: FieldUpdate.Author = .keyboard, field: String = "a") -> FieldUpdate {
        FieldUpdate(field: field, before: before, after: "", by: by, traits: InputTraits())
    }

    @Test func typingWhileSendingCollapsesIntoTheNewestText() {
        var feed = SourceFeed()
        feed.observe(update("", by: .app))
        _ = feed.next()
        feed.answered(update(""), hint: nil)
        feed.observe(update("h"))
        #expect(feed.next() == update("h"))
        feed.observe(update("he"))
        feed.observe(update("hey"))
        #expect(feed.next() == nil)
        feed.answered(update("h"), hint: nil)
        #expect(feed.next() == update("hey"))
        feed.answered(update("hey"), hint: nil)
        #expect(feed.next() == nil)
    }

    @Test func theTextBeforeASendIsAlwaysSent() {
        var feed = SourceFeed()
        feed.observe(update("h", by: .app))
        _ = feed.next()
        feed.observe(update("hey you"))
        feed.observe(update("", by: .app))
        feed.observe(update("n"))
        feed.observe(update("no"))
        feed.answered(update("h"), hint: nil)
        var sent: [FieldUpdate] = []
        while let next = feed.next() {
            sent.append(next)
            feed.answered(next, hint: nil)
        }
        #expect(sent == [update("hey you"), update("", by: .app), update("no")])
    }

    @Test func theSameTextIsSentOnce() {
        var feed = SourceFeed()
        feed.observe(update("", by: .app))
        feed.observe(update("hey"))
        feed.observe(update("hey", by: .app))
        #expect(feed.next() == update("", by: .app))
        feed.answered(update(""), hint: nil)
        #expect(feed.next() == update("hey"))
        feed.answered(update("hey"), hint: nil)
        #expect(feed.next() == nil)
    }

    @Test func aNewFieldIsTheAppsChange() {
        var feed = SourceFeed()
        feed.observe(update("hey"))
        #expect(feed.next() == update("hey", by: .app))
        feed.answered(update("hey"), hint: nil)
        feed.observe(update("hey", field: "b"))
        #expect(feed.next() == update("hey", by: .app, field: "b"))
    }

    @Test func aHintBelongsToItsField() {
        var feed = SourceFeed()
        feed.observe(update("you never listen"))
        feed.answered(feed.next()!, hint: "Careful")
        #expect(feed.hint(for: "a") == "Careful")
        #expect(feed.hint(for: "b") == nil)
        feed.observe(update("you never listen."))
        #expect(feed.hint(for: "a") == "Careful")
        feed.answered(feed.next()!, hint: nil)
        #expect(feed.hint(for: "a") == nil)
    }

    @Test func aDismissedHintStaysHiddenUntilItChanges() {
        var feed = SourceFeed()
        feed.observe(update("ugh"))
        feed.answered(feed.next()!, hint: "Careful")
        feed.dismissHint()
        #expect(feed.hint(for: "a") == nil)
        feed.observe(update("ugh!"))
        feed.answered(feed.next()!, hint: "Careful")
        #expect(feed.hint(for: "a") == nil)
        feed.observe(update("ugh!!"))
        feed.answered(feed.next()!, hint: "Really careful")
        #expect(feed.hint(for: "a") == "Really careful")
    }

    @Test func anUnreachableSourceIsToldOnlyTheNewestText() {
        var feed = SourceFeed()
        feed.observe(update("a", by: .app))
        _ = feed.next()
        feed.observe(update("ab"))
        feed.observe(update("", by: .app))
        feed.observe(update("c"))
        feed.failed()
        #expect(feed.next() == update("c"))
    }
}
