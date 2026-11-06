import UIKit
import KeyboardCore

public final class KeyboardView: UIView {
    public var onEvent: (KeyboardEvent) -> Void = { _ in }
    public var onGrid: (KeyGrid) -> Void = { _ in }
    public var resolve: (KeyGrid, CGPoint) -> (row: Int, key: Int)? = { grid, point in grid.index(atX: point.x, y: point.y) }
    public var globeTarget: ((UIControl) -> Void)?
    /// The record button, placed over the record key where the layout has one, in the key's shape.
    public var micKey: MicButton? {
        didSet {
            oldValue?.removeFromSuperview()
            setNeedsLayout()
        }
    }
    /// How far the space bar trackpad's finger travels to move the caret one character, -1 left or 1 right: the width
    /// of the character it crosses.
    public var advance: (Int) -> CGFloat = { _ in HostText.width(of: nil) }

    private(set) var layout = KeyboardLayout(rows: [])
    private(set) var signature = ""
    private(set) var metrics = KeyboardMetrics.phone(width: 390)
    private(set) var faceContext = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
    private(set) var theme = KeyboardTheme.lightCurrent
    private(set) var keyViews: [KeyView] = []
    private var grid = KeyGrid()
    private var rowKeys: [[KeyView]] = []
    private var globeControls: [UIControl] = []
    let callout = CalloutView()
    let trail = TrailView()
    let alternates = AlternatesView()
    private let expander = ExpanderView()
    private var animatesLayout = false
    var tracked: [ObjectIdentifier: TrackedTouch] = [:]

    public var characterPreview = CharacterPreview.attached
    public var slidesToType = true
    /// How far a touch on a letter must travel to be a swipe rather than a tap that wandered, in key widths: past the
    /// key's neighbor, which a tap's drift never reaches.
    static let swipeDistance: CGFloat = 0.8
    /// The keys whose hold opens the layer menu, what it offers, and the layout in use.
    public var menu: (keys: [Key], items: [KeyboardEvent], current: KeyboardEvent?) = ([], [], nil)
    var showsCallouts: Bool { characterPreview != .none && faceContext.device == .phone }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        clipsToBounds = false
        callout.isHidden = true
        alternates.isHidden = true
        expander.isHidden = true
        expander.addAction(UIAction { [unowned self] _ in onEvent(.oneHanded(.off)) }, for: .touchUpInside)
        addSubview(expander)
        addSubview(trail)
        addSubview(callout)
        addSubview(alternates)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func update(layout: KeyboardLayout, signature: String, metrics: KeyboardMetrics, faces: KeyFaceContext, theme: KeyboardTheme) {
        let rebuild = layout != self.layout
        let relayout = rebuild || metrics != self.metrics || signature != self.signature || theme != self.theme
        if rebuild {
            animatesLayout = false
        } else if metrics.margin != self.metrics.margin, window != nil {
            animatesLayout = true
        }
        self.layout = layout
        self.signature = signature
        self.metrics = metrics
        self.faceContext = faces
        self.theme = theme
        trail.color = theme.prominent.ui

        if rebuild { rebuildKeys() }
        if relayout { setNeedsLayout() }
        refreshFaces()
    }

    private func rebuildKeys() {
        keyViews.forEach { $0.removeFromSuperview() }
        globeControls.forEach { $0.removeFromSuperview() }
        rowKeys = layout.rows.map { row in
            row.compactMap { item -> KeyView? in
                guard case .key(let key) = item else { return nil }
                return KeyView(key: key)
            }
        }
        keyViews = rowKeys.flatMap { $0 }
        keyViews.forEach { insertSubview($0, belowSubview: trail) }
        globeControls = keyViews.filter { [.nextKeyboard, .globeSpacer].contains($0.key.action) }.map { view in
            let control = UIControl()
            if view.key.action == .nextKeyboard { globeTarget?(control) }
            addSubview(control)
            return control
        }
        for (_, touch) in tracked { touch.keyView = nil }
        grid = KeyGrid(layout, width: bounds.width, metrics: metrics.grid, signature: signature)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        grid = KeyGrid(layout, width: bounds.width, metrics: metrics.grid, signature: signature)
        onGrid(grid)
        guard animatesLayout else { return placeKeys() }
        animatesLayout = false
        UIView.animate(springDuration: 0.35, bounce: 0, options: .allowUserInteraction) { placeKeys() }
    }

    private func placeKeys() {
        var globes = globeControls.makeIterator()
        let scale = traitCollection.displayScale
        for (views, keys) in zip(rowKeys, grid.rows) {
            for (view, key) in zip(views, keys) {
                view.frame = CGRect(key.frame).rounded(scale: scale)
                view.layoutIfNeeded()
                if [.nextKeyboard, .globeSpacer].contains(view.key.action) { globes.next()?.frame = view.frame }
                if view.key.action == .dictate, let micKey {
                    view.isHidden = true
                    if micKey.superview !== self { addSubview(micKey) }
                    micKey.corner = metrics.cornerRadius
                    micKey.bounds.size = view.frame.size
                    micKey.center = CGPoint(x: view.frame.midX, y: view.frame.midY)
                }
            }
        }
        if case let (glyph, pointsRight)? = grid.expander {
            expander.place(CGRect(glyph), pointsRight: pointsRight, in: bounds, color: theme.expander.ui)
        }
        expander.isHidden = grid.expander == nil
        refreshFaces()
    }

    private func refreshFaces() {
        let metrics = keyMetrics
        for view in keyViews {
            view.theme = theme
            view.configure(KeyFace(view.key, trailing: view.center.x > bounds.midX, context: faceContext), metrics: metrics)
        }
    }

    /// The metrics keys and their callouts are drawn with: the theme's corners, sized from the narrowest key of the top
    /// row, a letter or a digit, as round as the roundness setting has them.
    var keyMetrics: KeyboardMetrics {
        var metrics = metrics
        guard let width = grid.rows.first?.map(\.frame.width).min() else { return metrics }
        if let shape = theme.keyShape { metrics.cornerRadius = shape.cornerRadius(letterWidth: width) }
        metrics.cornerRadius = metrics.rounded(metrics.cornerRadius, key: Size(width: width, height: metrics.keyHeight))
        return metrics
    }

    var drawableBounds: CGRect {
        bounds.inset(by: UIEdgeInsets(top: -frame.minY, left: 0, bottom: 0, right: 0))
    }

    func keyView(at point: CGPoint) -> KeyView? {
        resolve(grid, point).map { rowKeys[$0.row][$0.key] }
    }

    /// The top row reaches over what's above the keyboard (`Toolbar.topRowReach`); this view is in front of it.
    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: UIEdgeInsets(top: -Toolbar.topRowReach, left: 0, bottom: 0, right: 0)).contains(point)
    }
}
