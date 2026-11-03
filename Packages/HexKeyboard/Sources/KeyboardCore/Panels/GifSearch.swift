/// A GIF from KLIPY (docs/design.md, "GIF").
public struct Gif: Codable, Hashable, Sendable, Identifiable {
    public struct File: Codable, Hashable, Sendable {
        public var url: String
        public var width: Int
        public var height: Int

        public init(url: String, width: Int, height: Int) {
            self.url = url
            self.width = width
            self.height = height
        }
    }

    /// KLIPY's slug, which also fetches it again for recents.
    public var id: String
    public var title: String
    /// The small rendition the grid animates.
    public var preview: File
    /// The rendition that goes on the clipboard.
    public var full: File

    public init(id: String, title: String, preview: File, full: File) {
        self.id = id
        self.title = title
        self.preview = preview
        self.full = full
    }
}

/// What the GIF panel shows, and the one request it has out at a time. KLIPY's testing keys allow 100 requests an
/// hour, so keys typed while a search is out don't each send one: when it comes back, a single search goes out for
/// whatever the field holds then. Results only ever show for what the field holds. Scrolled to the end, a feed asks for
/// its next page while KLIPY has one.
public struct GifSearch: Sendable {
    public enum Feed: Hashable, Sendable {
        case trending
        case search(String)
        /// The GIFs you sent, newest first, by slug.
        case recents([String])
    }

    public enum Results: Hashable, Sendable {
        case loading
        case gifs([Gif])
        case failed
    }

    public private(set) var wanted: Feed = .trending
    private var inFlight: Feed?
    private var answers: [Feed: Results] = [:]
    /// The page each feed's results go on with, while KLIPY says there is one.
    private var next: [Feed: Int] = [:]

    public init() {}

    public var results: Results { answers[wanted] ?? .loading }

    /// The feed for what the field holds: trending when it's blank, else a search for its words.
    public static func feed(for field: String) -> Feed {
        let words = field.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.isEmpty ? .trending : .search(words)
    }

    /// Shows a feed, trying it again if it failed. Returns the request to send, if one should go out now.
    public mutating func want(_ feed: Feed) -> Feed? {
        wanted = feed
        if answers[feed] == .failed { answers[feed] = nil }
        return nextRequest()
    }

    /// The next page of what shows, when the panel is scrolled to its end: nil when there's none, or a request is out.
    public mutating func more() -> (feed: Feed, page: Int)? {
        guard inFlight == nil, case .gifs = answers[wanted], let page = next[wanted] else { return nil }
        inFlight = wanted
        return (wanted, page)
    }

    /// A request came back, with nil when it failed, and whether KLIPY has a page after it. A later page adds to what
    /// shows; one that failed ends the feed where it is. Returns the next request to send, if any.
    public mutating func received(_ gifs: [Gif]?, for feed: Feed, page: Int = 1, hasNext: Bool = false) -> Feed? {
        if inFlight == feed { inFlight = nil }
        next[feed] = gifs != nil && hasNext ? page + 1 : nil
        if page > 1 {
            if let gifs, case .gifs(let shown) = answers[feed] { answers[feed] = .gifs(shown + gifs.filter { !shown.contains($0) }) }
        } else {
            answers[feed] = gifs.map(Results.gifs) ?? .failed
        }
        return nextRequest()
    }

    private mutating func nextRequest() -> Feed? {
        guard inFlight == nil, answers[wanted] == nil else { return nil }
        if case .recents(let slugs) = wanted, slugs.isEmpty {
            answers[wanted] = .gifs([])
            return nil
        }
        inFlight = wanted
        return wanted
    }
}

/// The GIFs you sent from the panel, newest first, by KLIPY slug. KLIPY doesn't allow keeping its media, so the panel
/// fetches them again by slug.
public struct GifRecents: Codable, Hashable, Sendable {
    public private(set) var slugs: [String] = []

    static let capacity = 50

    public init() {}

    public mutating func use(_ slug: String) {
        slugs.removeAll { $0 == slug }
        slugs.insert(slug, at: 0)
        slugs = Array(slugs.prefix(Self.capacity))
    }
}
