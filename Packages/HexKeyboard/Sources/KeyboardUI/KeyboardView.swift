import UIKit
import KeyboardCore

enum KeyboardEvent {
    case down(Key, tapCount: Int)
    case up(Key)
    case type(Key, text: String)
    case trigger(Key)
    case slideTyped(Key, text: String)
    case cursor(offset: Int)
    case trackpad(active: Bool)
}

final class KeyboardView: UIView {
    var onEvent: (KeyboardEvent) -> Void = { _ in }
    var globeTarget: ((UIControl) -> Void)?

    private(set) var layout = KeyboardLayout(rows: [])
    private(set) var metrics = KeyboardMetrics.phone(width: 390)
    private(set) var faceContext = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
    private(set) var theme = KeyboardTheme.light
    private(set) var keyViews: [KeyView] = []
    private var rowBands: [ClosedRange<CGFloat>] = []
    private var rowKeys: [[KeyView]] = []
    private var globeControls: [UIControl] = []
    let callout = CalloutView()
    let alternates = AlternatesView()
    var tracked: [ObjectIdentifier: TrackedTouch] = [:]

    var showsCallouts: Bool { faceContext.device == .phone }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        clipsToBounds = false
        callout.isHidden = true
        alternates.isHidden = true
        addSubview(callout)
        addSubview(alternates)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(layout: KeyboardLayout, metrics: KeyboardMetrics, faces: KeyFaceContext, theme: KeyboardTheme) {
        let rebuild = layout != self.layout
        let relayout = rebuild || metrics != self.metrics
        self.layout = layout
        self.metrics = metrics
        self.faceContext = faces
        self.theme = theme

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
        keyViews.forEach { insertSubview($0, belowSubview: callout) }
        globeControls = keyViews.filter { $0.key.action == .nextKeyboard }.map { _ in
            let control = UIControl()
            globeTarget?(control)
            addSubview(control)
            return control
        }
        for (_, touch) in tracked { touch.keyView = nil }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let available = bounds.width - metrics.sideInset * 2 + metrics.keyGap
        let pitch = available / metrics.columns
        var y = metrics.topInset
        var globes = globeControls.makeIterator()
        rowBands = []

        for (index, row) in layout.rows.enumerated() {
            let height = layout.hasNumberRow && index == 0 ? metrics.numberRowHeight : metrics.keyHeight
            let fixed = row.compactMap(\.width.span).reduce(0, +)
            let fills = row.count { $0.width == .fill }
            let fillSpan = fills > 0 ? max(available / pitch - fixed, 0) / Double(fills) : 0
            var x = metrics.sideInset - metrics.keyGap / 2
            var views = rowKeys[index].makeIterator()

            for item in row {
                let width = (item.width.span ?? fillSpan) * pitch
                if case .key = item, let view = views.next() {
                    view.frame = CGRect(x: x + metrics.keyGap / 2, y: y, width: width - metrics.keyGap, height: height)
                    if view.key.action == .nextKeyboard { globes.next()?.frame = view.frame }
                }
                x += width
            }
            let top = index == 0 ? -CGFloat.infinity : y - metrics.rowGap / 2
            let bottom = index == layout.rows.count - 1 ? CGFloat.infinity : y + height + metrics.rowGap / 2
            rowBands.append(top...bottom)
            y += height + metrics.rowGap
        }
        refreshFaces()
    }

    private func refreshFaces() {
        for view in keyViews {
            view.theme = theme
            view.configure(KeyFace(view.key, trailing: view.center.x > bounds.midX, context: faceContext), metrics: metrics)
        }
    }

    var drawableBounds: CGRect {
        bounds.inset(by: UIEdgeInsets(top: -frame.minY, left: 0, bottom: 0, right: 0))
    }

    func keyView(at point: CGPoint) -> KeyView? {
        guard let row = rowBands.firstIndex(where: { $0.contains(point.y) }) else { return nil }
        return rowKeys[row].min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }
}
