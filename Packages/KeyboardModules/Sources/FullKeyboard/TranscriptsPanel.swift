import KeyboardStore
import KeyboardCore
import KeyboardUI
import UIKit

/// What you dictated (docs/design.md, "Transcripts"), from the app's copy (`TranscriptFeed`), newest first, in the
/// clipboard's rows: its text, and its words and age at the right. A tap types it. The copy is read as the panel opens,
/// off the main thread.
final class TranscriptsPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    var fullAccess: () -> Bool = { false }
    var onPaste: (String) -> Void = { _ in }
    var onTurnOn: () -> Void = {}
    var onClipboard: () -> Void = {}
    let placeholder = "Search transcripts"
    var glyph: UIImage? { UIImage(systemName: "text.bubble") }
    var accessories: [UIView] { [clipboard] }

    private struct Shown: Equatable {
        var query: String
        var compact: Bool
        var theme: KeyboardTheme
    }

    private var all: [TranscriptFeed.Entry]?
    private var entries: [TranscriptFeed.Entry] = []
    private var shown: Shown?
    private var opened = 0
    private let layout = UICollectionViewFlowLayout()
    private lazy var list = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let message = PanelNotice()
    private let clipboard = DrawerSwitch("Clipboard History", symbol: "list.clipboard", identifier: "iikb.transcripts.clipboard")

    override init(frame: CGRect) {
        super.init(frame: frame)
        list.backgroundColor = .clear
        list.showsVerticalScrollIndicator = false
        list.showsHorizontalScrollIndicator = false
        list.delaysContentTouches = false
        list.dataSource = self
        list.delegate = self
        list.accessibilityIdentifier = "iikb.transcripts"
        [list.topEdgeEffect, list.bottomEdgeEffect, list.leftEdgeEffect, list.rightEdgeEffect].forEach { $0.isHidden = true }
        list.register(ClipRow.self, forCellWithReuseIdentifier: "transcript")
        message.accessibilityIdentifier = "iikb.transcripts.message"
        message.onTurnOn = { [unowned self] in onTurnOn() }
        clipboard.addAction(UIAction { [unowned self] _ in onClipboard() }, for: .touchUpInside)
        list.addSubview(message)
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        opened += 1
        all = nil
        shown = nil
        guard fullAccess() else { return }
        let request = opened
        Task {
            let read = await Task.detached(priority: .userInitiated) { TranscriptFeed.read() }.value
            guard request == opened else { return }
            all = read
            refresh()
        }
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        clipboard.tintColor = theme.candidate.ui
        let next = Shown(query: query, compact: metrics.toolbar.isCompact, theme: theme)
        guard next != shown else { return }
        let moved = query != shown?.query
        shown = next
        refresh()
        if moved { list.contentOffset = .zero }
    }

    private func refresh() {
        guard let shown else { return }
        let query = shown.query.lowercased()
        entries = (all ?? []).filter { query.isEmpty || $0.text.lowercased().contains(query) }
        let missing: String? = fullAccess() ? nil : "Transcripts need Full Access."
        let empty: String? = all == nil || !entries.isEmpty ? nil : query.isEmpty ? "What you dictate shows up here." : "No transcript with “\(shown.query)”"
        message.show(missing ?? empty, turnOn: missing != nil, oneRow: shown.compact, theme: shown.theme)
        layout.scrollDirection = shown.compact ? .horizontal : .vertical
        list.reloadData()
        setNeedsLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let row = collectionView.dequeueReusableCell(withReuseIdentifier: "transcript", for: indexPath) as! ClipRow
        let entry = entries[indexPath.item]
        let detail = ClipboardHistory.length(of: entry.text, in: .words) + " · " + ClipboardHistory.age(of: entry.date, now: Date.now.timeIntervalSince1970)
        row.show(text: entry.text, detail: detail, pinned: false, compact: shown?.compact == true, theme: shown?.theme ?? .lightCurrent, holding: false)
        row.accessibilityIdentifier = "iikb.transcript.\(indexPath.item)"
        return row
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onPaste(entries[indexPath.item].text)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        list.frame = bounds
        let compact = shown?.compact == true, gap = 6.0
        message.frame = bounds
        layout.sectionInset = .zero
        layout.minimumLineSpacing = compact ? gap : 2
        layout.minimumInteritemSpacing = 0
        let size = compact ? CGSize(width: ((bounds.width - 2 * gap) / 3).rounded(.down), height: bounds.height) : CGSize(width: bounds.width, height: 44)
        if layout.itemSize != size { layout.itemSize = size }
        layout.invalidateLayout()
    }
}
