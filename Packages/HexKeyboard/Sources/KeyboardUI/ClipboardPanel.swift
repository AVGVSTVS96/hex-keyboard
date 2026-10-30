import KeyboardCore
import UIKit

/// The clipboard panel's results (docs/design.md, "Clipboard"): what you copied, pinned items first, as rows scrolling up
/// and down (cards in one row in the compact layout). A tap types the text, or puts an image back on the clipboard;
/// holding a row offers Pin and Delete.
final class ClipboardPanel: UIView, PanelContent {
    var fullAccess: () -> Bool = { false }
    var onPaste: (String) -> Void = { _ in }
    var onTurnOn: () -> Void = {}
    /// The search row's notice changed.
    var changed: () -> Void = {}
    let placeholder = "Search clipboard"
    var glyph: UIImage? { UIImage(systemName: "list.clipboard") }
    private(set) var notice: String?

    private struct Shown: Equatable {
        var items: [ClipboardHistory.Item]
        var message: String?
        var compact: Bool
        var theme: KeyboardTheme
        var holding: ClipboardHistory.Item.Content?
    }

    private let store: ClipboardStore
    private var query = ""
    private var compact = false
    private var theme = KeyboardTheme.lightCurrent
    private var holding: ClipboardHistory.Item.Content?
    private var shown: Shown?
    private let scroll = UIScrollView()
    private var rows: [ClipRow] = []
    private let message = UIButton(type: .system)

    init(store: ClipboardStore) {
        self.store = store
        super.init(frame: .zero)
        scroll.delaysContentTouches = false
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.accessibilityIdentifier = "hex.clipboard"
        [scroll.topEdgeEffect, scroll.bottomEdgeEffect, scroll.leftEdgeEffect, scroll.rightEdgeEffect].forEach { $0.isHidden = true }
        message.titleLabel?.font = .systemFont(ofSize: 15)
        message.titleLabel?.numberOfLines = 0
        message.titleLabel?.textAlignment = .center
        message.accessibilityIdentifier = "hex.clipboard.message"
        message.addAction(UIAction { [unowned self] _ in if message.tag == 1 { onTurnOn() } }, for: .touchUpInside)
        addSubview(scroll)
        addSubview(message)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        if fullAccess() { store.catchUp() }
        query = ""
        holding = nil
        notice = nil
        shown = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        if query != self.query { notice = nil }
        self.query = query
        self.theme = theme
        compact = metrics.toolbar.pills == nil
        refresh()
    }

    private func refresh() {
        let items = fullAccess() ? store.history.matching(query) : []
        let missing: String? = if !fullAccess() { "Clipboard needs Full Access." } else if store.refused { "To keep what you copy, set Paste from Other Apps to Allow." } else { nil }
        let empty: String? = items.isEmpty ? (query.isEmpty ? "Things you copy show up here." : "Nothing copied with “\(query)”") : nil
        let next = Shown(items: items, message: missing ?? empty, compact: compact, theme: theme, holding: holding)
        guard next != shown else { return }
        let moved = next.items.map(\.content) != shown?.items.map(\.content)
        shown = next

        let turnOn = missing != nil
        message.tag = turnOn ? 1 : 0
        message.isHidden = next.message == nil
        message.setAttributedTitle(next.message.map { text in
            let title = NSMutableAttributedString(string: text, attributes: [.foregroundColor: theme.candidate.ui, .font: UIFont.systemFont(ofSize: 15)])
            if turnOn { title.append(NSAttributedString(string: "\nTurn On", attributes: [.foregroundColor: theme.prominent.ui, .font: UIFont.systemFont(ofSize: 15, weight: .semibold)])) }
            return title
        }, for: .normal)

        rows.forEach { $0.removeFromSuperview() }
        rows = items.map { item in
            let row = ClipRow(item: item, compact: compact, theme: theme, thumbnail: { [store] in store.thumbnail($0, side: 96) })
            row.holding = item.content == holding
            row.addAction(UIAction { [unowned self] _ in pick(item) }, for: .touchUpInside)
            row.onHold = { [unowned self] in
                holding = item.content
                refresh()
            }
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
            scroll.addSubview(row)
            return row
        }
        if moved { scroll.contentOffset = .zero }
        setNeedsLayout()
    }

    private func pick(_ item: ClipboardHistory.Item) {
        guard holding == nil else {
            holding = nil
            return refresh()
        }
        switch item.content {
        case .text(let text): onPaste(text)
        case .image(let name):
            store.copy(image: name)
            notice = "Copied. Paste it in your message."
            changed()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let messageHeight = shown?.message == nil ? 0.0 : (rows.isEmpty ? bounds.height : 44)
        message.frame = CGRect(x: 0, y: 0, width: bounds.width, height: messageHeight)
        let top = rows.isEmpty ? 0 : messageHeight
        if compact {
            let gap = 6.0
            let width = ((bounds.width - 2 * gap) / 3).rounded(.down)
            for (index, row) in rows.enumerated() {
                row.frame = CGRect(x: Double(index) * (width + gap), y: top, width: width, height: bounds.height - top)
            }
            scroll.contentSize = CGSize(width: max(Double(rows.count) * (width + gap) - gap, 0), height: bounds.height)
        } else {
            for (index, row) in rows.enumerated() {
                row.frame = CGRect(x: 0, y: top + Double(index) * 46, width: bounds.width, height: 44)
            }
            scroll.contentSize = CGSize(width: bounds.width, height: top + max(Double(rows.count) * 46 - 2, 0))
        }
    }
}

/// One thing you copied: its pin, its text or a thumbnail, and how long ago; held, Pin and Delete in place of the time.
private final class ClipRow: UIControl {
    var onHold: () -> Void = {}
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    var holding = false { didSet { setNeedsLayout() } }
    private let item: ClipboardHistory.Item
    private let compact: Bool
    private let pin = UIImageView()
    private let text = UILabel()
    private let thumbnail = UIImageView()
    private let age = UILabel()
    private let pinButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let backdrop = UIView()
    private let fill: UIColor
    private let pressedFill: UIColor

    init(item: ClipboardHistory.Item, compact: Bool, theme: KeyboardTheme, thumbnail image: (String) -> UIImage?) {
        self.item = item
        self.compact = compact
        fill = compact ? theme.key.ui : .clear
        pressedFill = compact ? theme.keyPressed.ui : theme.label.ui.withAlphaComponent(0.12)
        super.init(frame: .zero)
        backdrop.isUserInteractionEnabled = false
        backdrop.layer.cornerRadius = 10
        backdrop.layer.cornerCurve = .continuous
        backdrop.backgroundColor = fill
        pin.image = UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
        pin.tintColor = theme.candidate.ui
        pin.contentMode = .center
        pin.isHidden = !item.pinned
        text.textColor = theme.label.ui
        text.font = .systemFont(ofSize: compact ? 14 : 16)
        age.textColor = theme.candidate.ui
        age.font = .systemFont(ofSize: compact ? 11 : 13)
        age.text = ClipboardHistory.age(of: item.found, now: Date.now.timeIntervalSince1970)
        age.textAlignment = compact ? .left : .right
        thumbnail.layer.cornerRadius = 6
        thumbnail.clipsToBounds = true
        thumbnail.contentMode = .scaleAspectFill
        switch item.content {
        case .text(let string):
            text.text = string.split(whereSeparator: \.isNewline).joined(separator: " ")
            thumbnail.isHidden = true
        case .image(let name):
            thumbnail.image = image(name)
            text.isHidden = true
        }
        for (button, symbol, label) in [(pinButton, item.pinned ? "pin.slash" : "pin", item.pinned ? "Unpin" : "Pin"), (deleteButton, "trash", "Delete")] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
            button.tintColor = button === deleteButton ? theme.record.ui : theme.label.ui
            button.accessibilityLabel = label
        }
        pinButton.accessibilityIdentifier = "hex.clipboard.pin"
        deleteButton.accessibilityIdentifier = "hex.clipboard.delete"
        pinButton.addAction(UIAction { [unowned self] _ in onPin() }, for: .touchUpInside)
        deleteButton.addAction(UIAction { [unowned self] _ in onDelete() }, for: .touchUpInside)
        [backdrop, pin, text, thumbnail, age].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        addSubview(pinButton)
        addSubview(deleteButton)
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hold)))
        isAccessibilityElement = false
        accessibilityIdentifier = "hex.clip.\(item.content.label)"
        text.accessibilityIdentifier = "hex.clip.text"
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { onHold() }
    }

    override var isHighlighted: Bool {
        didSet { backdrop.backgroundColor = isHighlighted || holding ? pressedFill : fill }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        backdrop.backgroundColor = isHighlighted || holding ? pressedFill : fill
        pinButton.isHidden = !holding
        deleteButton.isHidden = !holding
        age.isHidden = holding
        if compact {
            let inset = bounds.insetBy(dx: 10, dy: 6)
            pin.frame = CGRect(x: inset.maxX - 14, y: inset.minY, width: 14, height: 14)
            text.numberOfLines = 2
            text.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.width - (item.pinned ? 16 : 0), height: inset.height - 13)
            thumbnail.frame = CGRect(x: inset.minX, y: inset.minY, width: inset.height - 13, height: inset.height - 13)
            age.frame = CGRect(x: inset.minX, y: inset.maxY - 13, width: inset.width, height: 13)
            pinButton.frame = CGRect(x: inset.maxX - 64, y: inset.maxY - 30, width: 32, height: 30)
            deleteButton.frame = CGRect(x: inset.maxX - 32, y: inset.maxY - 30, width: 32, height: 30)
            return
        }
        pin.frame = CGRect(x: 0, y: 0, width: 16, height: bounds.height)
        let right = holding ? bounds.width - 84 : bounds.width - 60
        age.frame = CGRect(x: right, y: 0, width: bounds.width - right, height: bounds.height)
        thumbnail.frame = CGRect(x: 22, y: (bounds.height - 32) / 2, width: 32, height: 32)
        text.frame = CGRect(x: 22, y: 0, width: right - 30, height: bounds.height)
        pinButton.frame = CGRect(x: bounds.width - 84, y: 0, width: 42, height: bounds.height)
        deleteButton.frame = CGRect(x: bounds.width - 42, y: 0, width: 42, height: bounds.height)
    }
}

private extension ClipboardHistory.Item.Content {
    var label: String {
        switch self {
        case .text(let text): String(text.prefix(40))
        case .image(let name): name
        }
    }
}
