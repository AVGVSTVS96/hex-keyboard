import HexStore
import KeyboardCore
import KeyboardUI
import UIKit

/// The clipboard panel's results (docs/design.md, "Clipboard"): what you copied, pinned items first, as rows scrolling up
/// and down (cards in one row scrolling sideways in the compact layout). A tap types the text, or puts an image back on the clipboard;
/// holding a row offers Pin and Delete. Only the rows on screen are made, and their thumbnails decode off the main
/// thread, so a long history opens as fast as a short one.
final class ClipboardPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    var fullAccess: () -> Bool = { false }
    var onPaste: (String) -> Void = { _ in }
    var onTurnOn: () -> Void = {}
    /// The search row's notice changed.
    var changed: () -> Void = {}
    let placeholder = "Search clipboard"
    var glyph: UIImage? { UIImage(systemName: "list.clipboard") }
    private(set) var notice: String?

    private struct Shown: Equatable {
        var query: String
        var compact: Bool
        var theme: KeyboardTheme
    }

    private let store: ClipboardStore
    private var search = 0
    private var shown: Shown?
    private var items: [ClipboardHistory.Item] = []
    private var holding: ClipboardHistory.Item.Content?
    private let layout = UICollectionViewFlowLayout()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: layout)
    /// In the list's content, ahead of the rows, so in one row it scrolls away with them.
    private let message = PanelNotice()
    private let thumbnails = NSCache<NSString, UIImage>()

    init(store: ClipboardStore) {
        self.store = store
        super.init(frame: .zero)
        list.backgroundColor = .clear
        list.showsVerticalScrollIndicator = false
        list.showsHorizontalScrollIndicator = false
        list.delaysContentTouches = false
        list.dataSource = self
        list.delegate = self
        list.accessibilityIdentifier = "hex.clipboard"
        [list.topEdgeEffect, list.bottomEdgeEffect, list.leftEdgeEffect, list.rightEdgeEffect].forEach { $0.isHidden = true }
        list.register(ClipRow.self, forCellWithReuseIdentifier: "clip")
        list.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hold)))
        message.accessibilityIdentifier = "hex.clipboard.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        list.addSubview(message)
        addSubview(list)
        store.onChange = { [unowned self] in refresh() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        search += 1
        if fullAccess() { store.catchUp() }
        holding = nil
        notice = nil
        shown = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let next = Shown(query: query, compact: metrics.toolbar.isCompact, theme: theme)
        guard next != shown else { return }
        if query != shown?.query { notice = nil }
        shown = next
        refresh()
    }

    /// Runs only when the search, the look or the history changed, never on a keystroke that changed none of them.
    private func refresh() {
        guard let shown, window != nil else { return }
        search += 1
        let request = search
        Task {
            let items = fullAccess() && store.loaded ? await store.matching(shown.query) : []
            guard request == search else { return }
            display(items, shown: shown)
        }
    }

    private func display(_ items: [ClipboardHistory.Item], shown: Shown) {
        let loaded = fullAccess() && store.loaded
        let missing: String? = if !fullAccess() { "Clipboard needs Full Access." } else if store.refused { "To keep what you copy, set Paste from Other Apps to Allow." } else { nil }
        let empty: String? = loaded && items.isEmpty ? (shown.query.isEmpty ? "Things you copy show up here." : "Nothing copied with “\(shown.query)”") : nil
        message.show(missing ?? empty, turnOn: missing != nil, oneRow: shown.compact, theme: shown.theme)
        let moved = items.map(\.content) != self.items.map(\.content)
        self.items = items
        layout.scrollDirection = shown.compact ? .horizontal : .vertical
        list.reloadData()
        if moved { list.contentOffset = .zero }
        setNeedsLayout()
    }

    private func pick(_ item: ClipboardHistory.Item) {
        guard holding == nil else {
            holding = nil
            return list.reloadData()
        }
        switch item.content {
        case .text(let text): onPaste(text)
        case .textFile:
            let request = search
            Task {
                guard let text = await store.text(item.content), request == search, window != nil else { return }
                onPaste(text)
            }
        case .image(let name):
            store.copy(image: name)
            notice = "Copied. Paste it in your message."
            changed()
        }
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let indexPath = list.indexPathForItem(at: gesture.location(in: list)) else { return }
        holding = items[indexPath.item].content
        list.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let row = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipRow
        let item = items[indexPath.item]
        row.show(item, compact: shown?.compact == true, theme: shown?.theme ?? .lightCurrent, holding: item.content == holding)
        if case .image(let name) = item.content { thumbnail(name, for: row) }
        row.onPin = { [unowned self] in
            store.setPinned(!item.pinned, item.content)
            holding = nil
            refresh()
        }
        row.onDelete = { [unowned self] in
            store.remove(item.content)
            holding = nil
            refresh()
        }
        return row
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        pick(items[indexPath.item])
    }

    private func thumbnail(_ name: String, for row: ClipRow) {
        if let image = thumbnails.object(forKey: name as NSString) { return row.thumbnail = image }
        Task { [store] in
            let image = await Task.detached(priority: .userInitiated) { store.thumbnail(name, side: 96) }.value
            guard let image else { return }
            thumbnails.setObject(image, forKey: name as NSString)
            if row.shows(.image(name)) { row.thumbnail = image }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        list.frame = bounds
        let compact = shown?.compact == true, gap = 6.0
        let ahead = items.isEmpty || message.isHidden ? 0.0 : (compact ? bounds.width + gap : 46)
        message.frame = items.isEmpty ? bounds : CGRect(x: 0, y: 0, width: bounds.width, height: compact ? bounds.height : 44)
        layout.sectionInset = compact ? UIEdgeInsets(top: 0, left: ahead, bottom: 0, right: 0) : UIEdgeInsets(top: ahead, left: 0, bottom: 0, right: 0)
        layout.minimumLineSpacing = compact ? gap : 2
        layout.minimumInteritemSpacing = 0
        let size = compact ? CGSize(width: ((bounds.width - 2 * gap) / 3).rounded(.down), height: bounds.height) : CGSize(width: bounds.width, height: 44)
        if layout.itemSize != size { layout.itemSize = size }
        layout.invalidateLayout()
    }
}

/// One thing you copied: its pin, its text or a thumbnail, and how long ago; held, Pin and Delete in place of the time.
private final class ClipRow: UICollectionViewCell {
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    var thumbnail: UIImage? {
        get { image.image }
        set { image.image = newValue }
    }
    private var item: ClipboardHistory.Item?
    private var compact = false
    private var holding = false
    private let pin = UIImageView()
    private let text = UILabel()
    private let image = UIImageView()
    private let age = UILabel()
    private let pinButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let backdrop = UIView()
    private var fill = UIColor.clear
    private var pressedFill = UIColor.clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.layer.cornerRadius = 10
        backdrop.layer.cornerCurve = .continuous
        pin.image = UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
        pin.contentMode = .center
        image.layer.cornerRadius = 6
        image.clipsToBounds = true
        image.contentMode = .scaleAspectFill
        pinButton.accessibilityIdentifier = "hex.clipboard.pin"
        deleteButton.accessibilityIdentifier = "hex.clipboard.delete"
        deleteButton.accessibilityLabel = "Delete"
        deleteButton.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        pinButton.addAction(UIAction { [unowned self] _ in onPin() }, for: .touchUpInside)
        deleteButton.addAction(UIAction { [unowned self] _ in onDelete() }, for: .touchUpInside)
        [backdrop, pin, text, image, age].forEach {
            $0.isUserInteractionEnabled = false
            contentView.addSubview($0)
        }
        contentView.addSubview(pinButton)
        contentView.addSubview(deleteButton)
        text.accessibilityIdentifier = "hex.clip.text"
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ item: ClipboardHistory.Item, compact: Bool, theme: KeyboardTheme, holding: Bool) {
        if item.content != self.item?.content { image.image = nil }
        self.item = item
        self.compact = compact
        self.holding = holding
        fill = compact ? theme.key.ui : .clear
        pressedFill = compact ? theme.keyPressed.ui : theme.label.ui.withAlphaComponent(0.12)
        pin.tintColor = theme.candidate.ui
        pin.isHidden = !item.pinned
        text.textColor = theme.label.ui
        text.font = .systemFont(ofSize: compact ? 14 : 16)
        text.numberOfLines = compact ? 2 : 1
        age.textColor = theme.candidate.ui
        age.font = .systemFont(ofSize: compact ? 11 : 13)
        age.text = ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970)
        age.textAlignment = compact ? .left : .right
        switch item.content {
        case .text(let string), .textFile(_, let string):
            text.text = String(string.prefix(300)).split(whereSeparator: \.isNewline).joined(separator: " ")
            text.isHidden = false
            image.isHidden = true
        case .image:
            text.isHidden = true
            image.isHidden = false
        }
        pinButton.setImage(UIImage(systemName: item.pinned ? "pin.slash" : "pin", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
        pinButton.accessibilityLabel = item.pinned ? "Unpin" : "Pin"
        pinButton.tintColor = theme.label.ui
        deleteButton.tintColor = theme.record.ui
        accessibilityIdentifier = "hex.clip.\(item.content.label)"
        setNeedsLayout()
    }

    func shows(_ content: ClipboardHistory.Item.Content) -> Bool { item?.content == content }

    override var isHighlighted: Bool {
        didSet { backdrop.backgroundColor = isHighlighted || holding ? pressedFill : fill }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        backdrop.frame = bounds
        backdrop.backgroundColor = isHighlighted || holding ? pressedFill : fill
        pinButton.isHidden = !holding
        deleteButton.isHidden = !holding
        age.isHidden = holding
        if compact {
            let inset = bounds.insetBy(dx: 10, dy: 6)
            pin.frame = CGRect(x: inset.maxX - 14, y: inset.minY, width: 14, height: 14)
            text.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.width - (item?.pinned == true ? 16 : 0), height: inset.height - 13)
            image.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.height - 13, height: inset.height - 13)
            age.frame = CGRect(x: inset.minX, y: inset.maxY - 13, width: inset.width, height: 13)
            pinButton.frame = CGRect(x: inset.maxX - 64, y: inset.maxY - 30, width: 32, height: 30)
            deleteButton.frame = CGRect(x: inset.maxX - 32, y: inset.maxY - 30, width: 32, height: 30)
            return
        }
        pin.frame = CGRect(x: 0, y: 0, width: 16, height: bounds.height)
        let right = holding ? bounds.width - 84 : bounds.width - 60
        age.frame = CGRect(x: right, y: 0, width: bounds.width - right, height: bounds.height)
        image.frame = CGRect(x: 22, y: (bounds.height - 32) / 2, width: 32, height: 32)
        text.frame = CGRect(x: 22, y: 0, width: right - 30, height: bounds.height)
        pinButton.frame = CGRect(x: bounds.width - 84, y: 0, width: 42, height: bounds.height)
        deleteButton.frame = CGRect(x: bounds.width - 42, y: 0, width: 42, height: bounds.height)
    }
}

private extension ClipboardHistory.Item.Content {
    var label: String {
        switch self {
        case .text(let text), .textFile(_, let text): String(text.prefix(40))
        case .image(let name): name
        }
    }
}
