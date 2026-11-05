import Testing
@testable import KeyboardCore

struct GifSearchTests {
    func gif(_ id: String) -> Gif {
        Gif(id: id, title: id, preview: .init(url: "https://x/\(id)-sm.gif", width: 100, height: 80), full: .init(url: "https://x/\(id).gif", width: 400, height: 320))
    }

    @Test func aBlankFieldShowsTrendingAndSpacesDontMakeANewSearch() {
        #expect(GifSearch.feed(for: "") == .trending)
        #expect(GifSearch.feed(for: "  ") == .trending)
        #expect(GifSearch.feed(for: " happy  birthday ") == .search("happy birthday"))
    }

    @Test func keysTypedWhileASearchIsOutBecomeOneSearchForTheNewestText() {
        var search = GifSearch()
        #expect(search.want(.search("c")) == .search("c"))
        #expect(search.want(.search("ca")) == nil, "one request out at a time")
        #expect(search.want(.search("cat")) == nil)
        #expect(search.results == .loading)
        #expect(search.received([gif("c1")], for: .search("c")) == .search("cat"), "it skips ca")
        #expect(search.results == .loading, "c's results never show for cat")
        #expect(search.received([gif("cat1")], for: .search("cat")) == nil)
        #expect(search.results == .gifs([gif("cat1")]))
    }

    @Test func goingBackToAnEarlierSearchShowsItsResultsWithoutAsking() {
        var search = GifSearch()
        _ = search.want(.search("c"))
        _ = search.received([gif("c1")], for: .search("c"))
        _ = search.want(.search("ca"))
        #expect(search.want(.search("c")) == nil)
        #expect(search.results == .gifs([gif("c1")]))
        #expect(search.received([], for: .search("ca")) == nil)
        #expect(search.results == .gifs([gif("c1")]))
    }

    @Test func aFailedSearchSaysSoAndTheNextKeyTriesAgain() {
        var search = GifSearch()
        _ = search.want(.trending)
        #expect(search.received(nil, for: .trending) == nil, "no retry on its own")
        #expect(search.results == .failed)
        #expect(search.want(.trending) == .trending)
        #expect(search.results == .loading)
    }

    @Test func theEndOfTheResultsAsksForTheNextPageOnceWhileKlipyHasOne() throws {
        var search = GifSearch()
        _ = search.want(.search("cat"))
        #expect(search.more() == nil, "nothing shows yet")
        _ = search.received([gif("cat1")], for: .search("cat"), hasNext: true)
        let asked = search.more()
        let more = try #require(asked)
        #expect(more.feed == .search("cat") && more.page == 2)
        #expect(search.more() == nil, "one request out at a time")
        _ = search.received([gif("cat1"), gif("cat2")], for: .search("cat"), page: 2, hasNext: false)
        #expect(search.results == .gifs([gif("cat1"), gif("cat2")]), "a page adds to what shows, without repeats")
        #expect(search.more() == nil, "KLIPY had no more")
    }

    @Test func aFailedPageKeepsWhatShows() throws {
        var search = GifSearch()
        _ = search.want(.trending)
        _ = search.received([gif("t1")], for: .trending, hasNext: true)
        let asked = search.more()
        let more = try #require(asked)
        _ = search.received(nil, for: more.feed, page: more.page)
        #expect(search.results == .gifs([gif("t1")]))
        #expect(search.more() == nil, "it doesn't keep asking at the end")
    }

    @Test func noRecentsNeedsNoRequest() {
        var search = GifSearch()
        #expect(search.want(.recents([])) == nil)
        #expect(search.results == .gifs([]))
        #expect(search.want(.recents(["a", "b"])) == .recents(["a", "b"]))
    }

    @Test func recentsKeepTheLast50NewestFirst() {
        var recents = GifRecents()
        for i in 0 ..< 55 { recents.use("\(i)") }
        recents.use("10")
        #expect(recents.slugs.count == 50)
        #expect(recents.slugs.prefix(3) == ["10", "54", "53"])
        #expect(!recents.slugs.contains("4"))
    }
}
