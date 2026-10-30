import UIKit
import KeyboardCore

/// What a panel shows above its search field. Each panel (emoji, GIFs, the clipboard) brings its own; `PanelView`
/// draws the search row under it and the keys type into the field.
protocol PanelContent: UIView {
    var placeholder: String { get }
    /// The field's leading glyph.
    var glyph: UIImage? { get }
    /// Buttons at the field's right end, before its clear button.
    var accessories: [UIView] { get }
    /// The results for `query`. Called on every render; redraw only when something changed, so results never move
    /// under a finger.
    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics)
    /// The panel just opened.
    func reset()
}

extension PanelContent {
    var glyph: UIImage? { UIImage(systemName: "magnifyingglass") }
    var accessories: [UIView] { [] }
    func reset() {}
}

/// A panel in place of the bar and the pill row: results on top, then a back button and the search field.
final class PanelView: UIView {
    var onClose: () -> Void = {}
    var onClear: () -> Void = {}
    var block = (minX: CGFloat(0), maxX: CGFloat(0)) { didSet { if block != oldValue { setNeedsLayout() } } }
    private(set) var content: PanelContent?
    private var toolbar = KeyboardMetrics.phone(width: 390).toolbar
    private let back = UIButton(type: .custom)
    private let field = SearchField()

    override init(frame: CGRect) {
        super.init(frame: frame)
        back.accessibilityIdentifier = "hex.panel.back"
        back.accessibilityLabel = "Back"
        back.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)), for: .normal)
        back.addAction(UIAction { [unowned self] _ in onClose() }, for: .touchUpInside)
        field.onClear = { [unowned self] in onClear() }
        addSubview(back)
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }

    func open(_ content: PanelContent?) {
        guard content !== self.content else { return }
        self.content?.removeFromSuperview()
        self.content = content
        guard let content else { return }
        content.reset()
        field.accessories = content.accessories
        insertSubview(content, at: 0)
        setNeedsLayout()
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        if metrics.toolbar != toolbar {
            toolbar = metrics.toolbar
            setNeedsLayout()
        }
        back.tintColor = theme.label.ui
        field.show(query, placeholder: content?.placeholder ?? "", glyph: content?.glyph, theme: theme)
        content?.show(query: query, theme: theme, metrics: metrics)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = block.maxX - block.minX
        content?.frame = CGRect(x: block.minX, y: toolbar.top, width: width, height: toolbar.results)
        let row = CGRect(x: block.minX, y: toolbar.top + toolbar.results + Toolbar.fieldGap, width: width, height: toolbar.field)
        back.frame = CGRect(x: row.minX, y: row.minY, width: 36, height: row.height)
        field.frame = CGRect(x: back.frame.maxX + 4, y: row.minY, width: row.maxX - back.frame.maxX - 4, height: row.height)
    }
}

/// A panel's search field: a glyph, what the keys typed (or the placeholder) and the cursor, its accessories, and a
/// clear button once there's text. It takes no taps of its own: the keys below type into it.
private final class SearchField: UIView {
    var onClear: () -> Void = {}
    var accessories: [UIView] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            accessories.forEach(addSubview)
            setNeedsLayout()
        }
    }
    private let glyph = UIImageView()
    private let label = UILabel()
    private let caret = UIView()
    private let clear = UIButton(type: .custom)
    private var query = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.panel.search"
        isAccessibilityElement = true
        accessibilityTraits = .searchField
        layer.cornerCurve = .continuous
        glyph.contentMode = .center
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        label.font = .systemFont(ofSize: 17)
        caret.layer.cornerRadius = 1
        clear.accessibilityIdentifier = "hex.panel.clear"
        clear.accessibilityLabel = "Clear"
        clear.addAction(UIAction { [unowned self] _ in onClear() }, for: .touchUpInside)
        [glyph, label, caret].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        addSubview(clear)
        blink()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ query: String, placeholder: String, glyph image: UIImage?, theme: KeyboardTheme) {
        if query != self.query { setNeedsLayout() }
        self.query = query
        accessibilityLabel = placeholder
        accessibilityValue = query
        label.text = query.isEmpty ? placeholder : query
        label.textColor = query.isEmpty ? theme.candidate.ui : theme.label.ui
        glyph.image = image
        glyph.tintColor = theme.candidate.ui
        caret.backgroundColor = theme.prominent.ui
        backgroundColor = theme.searchField.ui
        clear.isHidden = query.isEmpty
        let mark = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        clear.setImage(Self.clearImage(mark: mark, circle: theme.candidate.ui, field: theme.searchField.ui), for: .normal)
    }

    /// The caret blinks the way UIKit's does, on Core Animation's clock rather than a timer.
    private func blink() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        caret.layer.add(animation, forKey: "blink")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { blink() }
    }

    private static func clearImage(mark: UIImage?, circle: UIColor, field: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
            circle.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 20, height: 20)).fill()
            guard let mark = mark?.withTintColor(field, renderingMode: .alwaysOriginal) else { return }
            mark.draw(at: CGPoint(x: (20 - mark.size.width) / 2, y: (20 - mark.size.height) / 2))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        layer.cornerRadius = bounds.height / 2
        glyph.frame = CGRect(x: 14, y: 0, width: 20, height: bounds.height)
        var right = bounds.width - 12
        if !clear.isHidden {
            clear.frame = CGRect(x: right - 28, y: 0, width: 28, height: bounds.height)
            right = clear.frame.minX
        }
        for accessory in accessories.reversed() {
            accessory.frame = CGRect(x: right - 32, y: 0, width: 32, height: bounds.height)
            right = accessory.frame.minX
        }
        let text = glyph.frame.maxX + 6
        let start = query.isEmpty ? text + 4 : text
        let width = min(label.intrinsicContentSize.width, right - start - 4)
        label.frame = CGRect(x: start, y: 0, width: max(width, 0), height: bounds.height)
        let typed = query.isEmpty ? 0 : label.frame.width
        caret.frame = CGRect(x: (text + typed + 1).rounded(scale: scale), y: ((bounds.height - 22) / 2).rounded(scale: scale), width: 2, height: 22)
    }
}
