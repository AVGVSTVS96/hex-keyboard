import ImageIO
import KeyboardCore
import UIKit
import UniformTypeIdentifiers

/// The GIF panel's results (docs/design.md, "GIF"): KLIPY's GIFs in two rows that scroll sideways (one in the compact
/// layout), each at its own aspect ratio. A tap puts the GIF on the clipboard to paste, a hold lifts it to drag into the
/// app's field; the clock shows the ones you sent.
final class GifPanel: UIView, PanelContent, UIScrollViewDelegate {
    var fullAccess: () -> Bool = { false }
    /// A GIF went on the clipboard, at this change count.
    var onCopied: (Int) -> Void = { _ in }
    var onTurnOn: () -> Void = {}
    /// The search row's notice changed.
    var changed: () -> Void = {}
    /// Empties the search, as the clock does, so recents never sit under words they don't match.
    var clearSearch: () -> Void = {}
    let placeholder = "Search KLIPY"
    var glyph: UIImage? { Panel.gifGlyph }
    var accessories: [UIView] { [clock] }
    private(set) var notice: String?

    private let klipy: Klipy
    private var search = GifSearch()
    private var recents = GifRecents()
    private var showsRecents = false
    private var query: String?
    private var shown: GifSearch.Results?
    /// The GIF last tapped, whose download is the one that reaches the clipboard.
    private var copying: Gif?
    private var theme = KeyboardTheme.lightCurrent
    private var rows = 2
    private let scroll = UIScrollView()
    private var tiles: [GifTile] = []
    private let message = UILabel()
    private let turnOn = UIButton(type: .system)
    private let clock = UIButton(type: .custom)

    init(klipy: Klipy) {
        self.klipy = klipy
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delaysContentTouches = false
        scroll.delegate = self
        scroll.accessibilityIdentifier = "hex.gifs"
        [scroll.topEdgeEffect, scroll.bottomEdgeEffect, scroll.leftEdgeEffect, scroll.rightEdgeEffect].forEach { $0.isHidden = true }
        message.font = .systemFont(ofSize: 15)
        message.textAlignment = .center
        message.numberOfLines = 2
        turnOn.setTitle("Turn On", for: .normal)
        turnOn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        turnOn.accessibilityIdentifier = "hex.gifs.turnOn"
        turnOn.addAction(UIAction { [unowned self] _ in onTurnOn() }, for: .touchUpInside)
        clock.accessibilityIdentifier = "hex.gifs.recents"
        clock.accessibilityLabel = "Recent GIFs"
        clock.setImage(UIImage(systemName: "clock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        clock.addAction(UIAction { [unowned self] _ in
            showsRecents.toggle()
            query = nil
            notice = nil
            showsRecents ? clearSearch() : changed()
        }, for: .touchUpInside)
        [scroll, message, turnOn].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        recents = Self.loadRecents()
        showsRecents = false
        query = nil
        notice = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        rows = metrics.toolbar.pills == nil ? 1 : 2
        if theme != self.theme {
            self.theme = theme
            message.textColor = theme.candidate.ui
            turnOn.tintColor = theme.prominent.ui
            tiles.forEach { $0.backgroundColor = theme.key.ui }
        }
        clock.tintColor = showsRecents ? theme.prominent.ui : theme.candidate.ui
        guard query != self.query else { return }
        if self.query != nil, !query.isEmpty { showsRecents = false }
        self.query = query
        notice = nil
        if fullAccess(), let request = search.want(showsRecents ? .recents(recents.slugs) : GifSearch.feed(for: query)) { fetch(request) }
        refresh()
    }

    private func fetch(_ feed: GifSearch.Feed) {
        Task { [weak self, klipy] in
            let gifs = await klipy.gifs(feed)
            guard let self else { return }
            if let next = search.received(gifs, for: feed) { fetch(next) }
            refresh()
        }
    }

    /// Lays the results out again only when they changed, so GIFs never move under a finger.
    private func refresh() {
        let results: GifSearch.Results = fullAccess() ? search.results : .failed
        let text: String? = switch results {
        case _ where !fullAccess(): "GIF search needs Full Access."
        case .failed: "Couldn't reach KLIPY."
        case .gifs([]) where showsRecents: "GIFs you send show up here."
        case .gifs([]): "No GIFs for “\(GifSearch.feed(for: query ?? "").words)”"
        default: nil
        }
        message.text = text
        message.isHidden = text == nil
        turnOn.isHidden = fullAccess()
        guard results != shown else { return }
        shown = results
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []
        if case .gifs(let gifs) = results {
            tiles = gifs.map { gif in
                let tile = GifTile(gif: gif, fill: theme.key.ui)
                tile.addAction(UIAction { [unowned self, unowned tile] _ in copy(tile) }, for: .touchUpInside)
                tile.dropped = { [weak self] in self?.sent(gif) }
                scroll.addSubview(tile)
                return tile
            }
        }
        scroll.contentOffset = .zero
        setNeedsLayout()
    }

    private func copy(_ tile: GifTile) {
        let gif = tile.gif
        copying = gif
        tile.alpha = 0.5
        Task { [weak self] in
            let data = await GifClipboard.download(gif)
            tile.alpha = 1
            guard let self, copying == gif else { return }
            copying = nil
            if let data {
                onCopied(GifClipboard.put(data))
                sent(gif)
            }
            notice = data == nil ? "Couldn't copy that GIF." : "Copied. Paste it, or hold a GIF to drag it in."
            changed()
        }
    }

    private func sent(_ gif: Gif) {
        recents.use(Klipy.base(gif.id))
        Self.save(recents)
        klipy.shared(gif, search: query ?? "")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        message.frame = bounds.insetBy(dx: 16, dy: 0).offsetBy(dx: 0, dy: turnOn.isHidden ? 0 : -14)
        turnOn.frame = CGRect(x: 0, y: bounds.midY + 8, width: bounds.width, height: 30)
        let gap = 6.0
        let height = ((bounds.height - gap * Double(rows - 1)) / Double(rows)).rounded(.down)
        var ends = Array(repeating: 0.0, count: rows)
        for tile in tiles {
            let row = ends.indices.min { ends[$0] < ends[$1] }!
            let ratio = Double(tile.gif.preview.width) / Double(max(tile.gif.preview.height, 1))
            let width = (height * min(max(ratio, 0.5), 2.5)).rounded()
            tile.frame = CGRect(x: ends[row], y: Double(row) * (height + gap), width: width, height: height)
            ends[row] += width + gap
        }
        scroll.contentSize = CGSize(width: max((ends.max() ?? gap) - gap, 0), height: bounds.height)
        animateVisible()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        animateVisible()
    }

    /// Only the tiles on screen load and animate; the rest drop their frames, since a keyboard's memory is small.
    private func animateVisible() {
        let visible = scroll.bounds.insetBy(dx: -40, dy: 0)
        for tile in tiles { tile.isOnScreen = window != nil && visible.intersects(tile.frame) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        animateVisible()
    }

    private static var recentsURL: URL { URL.applicationSupportDirectory.appending(path: "gif-recents.json") }

    private static func loadRecents() -> GifRecents {
        (try? JSONDecoder().decode(GifRecents.self, from: Data(contentsOf: recentsURL))) ?? GifRecents()
    }

    private static func save(_ recents: GifRecents) {
        try? FileManager.default.createDirectory(at: recentsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(recents).write(to: recentsURL, options: .atomic)
    }
}

private extension GifSearch.Feed {
    var words: String {
        if case .search(let words) = self { return words }
        return ""
    }
}

/// One GIF: the key fill while it loads, then its frames, played by ImageIO one at a time while it's on screen. Held, it
/// lifts out of the keyboard as the GIF's file, which the app takes in where it's dropped.
private final class GifTile: UIControl, UIDragInteractionDelegate {
    let gif: Gif
    var dropped: () -> Void = {}
    var isOnScreen = false { didSet { if isOnScreen != oldValue { isOnScreen ? play() : stop() } } }
    private let image = UIImageView()
    private var data: Data?
    private var download: Task<Void, Never>?
    private var playing: PlayToken?

    init(gif: Gif, fill: UIColor) {
        self.gif = gif
        super.init(frame: .zero)
        backgroundColor = fill
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true
        image.contentMode = .scaleAspectFill
        image.isUserInteractionEnabled = false
        addSubview(image)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = gif.title.isEmpty ? "GIF" : gif.title
        accessibilityIdentifier = "hex.gif.\(gif.id)"
        let drag = UIDragInteraction(delegate: self)
        drag.isEnabled = true
        addInteraction(drag)
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.gif.identifier, visibility: .all) { [gif] done in
            Task { done(await GifClipboard.download(gif), nil) }
            return nil
        }
        return [UIDragItem(itemProvider: provider)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        if operation == .copy { dropped() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet { image.alpha = isHighlighted ? 0.6 : 1 }
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        isOnScreen = false
        download?.cancel()
    }

    private func play() {
        guard let data else { return load() }
        let token = PlayToken()
        playing = token
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, frame, stop in
            let playing = MainActor.assumeIsolated {
                guard let self, !token.stopped else { return false }
                self.image.image = UIImage(cgImage: frame)
                return true
            }
            if !playing { stop.pointee = true }
        }
    }

    private func stop() {
        playing?.stopped = true
        playing = nil
        image.image = nil
    }

    private func load() {
        guard download == nil, let url = URL(string: gif.preview.url) else { return }
        download = Task { [weak self] in
            let loaded = try? await URLSession.shared.data(from: url)
            guard let self else { return }
            download = nil
            guard let (data, response) = loaded, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            self.data = data
            if isOnScreen { play() }
        }
    }
}

private final class PlayToken {
    var stopped = false
}
