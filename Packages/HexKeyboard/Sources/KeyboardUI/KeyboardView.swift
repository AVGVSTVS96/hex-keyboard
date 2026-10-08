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
    private var metrics = KeyboardMetrics.phone(width: 390)
    private var faceContext = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
    private var theme = KeyboardTheme.light
    private var keyViews: [KeyView] = []
    private var rowBands: [ClosedRange<CGFloat>] = []
    private var rowKeys: [[KeyView]] = []
    private var globeControls: [UIControl] = []
    private let callout = CalloutView()
    private let alternates = AlternatesView()
    private var tracked: [ObjectIdentifier: TrackedTouch] = [:]

    private var showsCallouts: Bool { faceContext.device == .phone }

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
        for view in keyViews {
            view.theme = theme
            view.configure(KeyFace(view.key, trailing: view.center.x > bounds.midX, context: faces), metrics: metrics)
        }
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
        let pitch = (bounds.width - metrics.sideInset * 2 + metrics.keyGap) / metrics.columns
        var y = metrics.topInset
        rowBands = []
        var globes = globeControls.makeIterator()

        for (index, row) in layout.rows.enumerated() {
            let height = layout.hasNumberRow && index == 0 ? metrics.numberRowHeight : metrics.keyHeight
            let fixed = row.reduce(0) { $0 + Self.span(of: $1) }
            let fills = CGFloat(row.filter(Self.isFill).count)
            let available = bounds.width - metrics.sideInset * 2 + metrics.keyGap
            let fillSpan = fills > 0 ? max(available / pitch - fixed, 0) / fills : 0
            var x = metrics.sideInset - metrics.keyGap / 2
            var views = rowKeys[index].makeIterator()

            for item in row {
                let span = Self.isFill(item) ? fillSpan : Self.span(of: item)
                let width = span * pitch
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
        for view in keyViews {
            view.configure(KeyFace(view.key, trailing: view.center.x > bounds.midX, context: faceContext), metrics: metrics)
        }
    }

    private static func isFill(_ item: RowItem) -> Bool {
        switch item {
        case .key(let key): key.width == .fill
        case .spacer(let width): width == .fill
        }
    }

    private static func span(of item: RowItem) -> CGFloat {
        let width: KeyWidth = switch item {
        case .key(let key): key.width
        case .spacer(let width): width
        }
        return switch width {
        case .input: 1
        case .pitch(let value): value
        case .fill: 0
        }
    }

    private var drawableBounds: CGRect {
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

extension KeyboardView {
    final class TrackedTouch {
        enum Mode { case typing, alternates, trackpad, slide }

        weak var keyView: KeyView?
        var mode = Mode.typing
        var flicked = false
        let start: CGPoint
        var lastCursorX: CGFloat
        var hold: Timer?

        init(keyView: KeyView, start: CGPoint) {
            self.keyView = keyView
            self.start = start
            self.lastCursorX = start.x
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let view = keyView(at: point) else { continue }
            rollOver()
            let tracked = TrackedTouch(keyView: view, start: point)
            self.tracked[ObjectIdentifier(touch)] = tracked
            press(view, tracked: tracked)
            onEvent(.down(view.key, tapCount: touch.tapCount))
            if case .layer = view.key.action { tracked.mode = .slide }
            scheduleHold(for: tracked)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let tracked = tracked[ObjectIdentifier(touch)] else { continue }
            let point = touch.location(in: self)
            switch tracked.mode {
            case .alternates:
                alternates.track(point)
            case .trackpad:
                let step: CGFloat = 9
                let offset = Int((point.x - tracked.lastCursorX) / step)
                if offset != 0 {
                    tracked.lastCursorX += CGFloat(offset) * step
                    onEvent(.cursor(offset: offset))
                }
            case .typing, .slide:
                if let flick = flickTarget(tracked, point) {
                    tracked.hold?.invalidate()
                    tracked.flicked = flick
                    tracked.keyView?.isFlicked = flick
                    continue
                }
                guard let view = keyView(at: point), view !== tracked.keyView,
                      tracked.mode == .slide || (view.key.isInput && tracked.keyView?.key.isInput == true) else { continue }
                tracked.keyView?.isPressed = false
                tracked.keyView = view
                tracked.hold?.invalidate()
                press(view, tracked: tracked)
                scheduleHold(for: tracked)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let tracked = tracked.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finish(tracked, commit: true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let tracked = tracked.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finish(tracked, commit: false)
        }
    }

    private func rollOver() {
        for (id, other) in tracked where other.mode == .typing && other.keyView?.key.isInput == true {
            tracked.removeValue(forKey: id)
            finish(other, commit: true)
        }
    }

    private func finish(_ tracked: TrackedTouch, commit: Bool) {
        tracked.hold?.invalidate()
        callout.hide()
        guard let view = tracked.keyView else { return }
        view.isPressed = false
        view.isFlicked = false
        defer { onEvent(.up(view.key)) }

        switch tracked.mode {
        case .alternates:
            if commit, let text = alternates.selected { onEvent(.type(view.key, text: text)) }
            alternates.hide()
        case .trackpad:
            setLabelsVisible(true)
            onEvent(.trackpad(active: false))
        case .slide:
            if commit, view.key.isInput, let text = text(for: view.key, flicked: tracked.flicked) {
                onEvent(.slideTyped(view.key, text: text))
            }
        case .typing:
            guard commit else { return }
            if let text = text(for: view.key, flicked: tracked.flicked) {
                onEvent(.type(view.key, text: text))
            } else if view.key.action == .space {
                onEvent(.type(view.key, text: " "))
            } else {
                onEvent(.trigger(view.key))
            }
        }
    }

    private func press(_ view: KeyView, tracked: TrackedTouch) {
        view.isPressed = !(showsCallouts && view.key.text(shifted: false) != nil)
        show(tracked)
    }

    private func show(_ tracked: TrackedTouch) {
        guard showsCallouts, tracked.mode != .alternates, let view = tracked.keyView,
              let text = text(for: view.key, flicked: tracked.flicked) else { return callout.hide() }
        callout.show(displayed(text), over: view.frame, in: drawableBounds, metrics: metrics, theme: theme)
    }

    private func text(for key: Key, flicked: Bool) -> String? {
        key.text(shifted: faceContext.shift.isUppercase, flicked: flicked)
    }

    private func displayed(_ text: String) -> String {
        faceContext.shift.isUppercase ? text.uppercased() : text
    }

    private func flickTarget(_ tracked: TrackedTouch, _ point: CGPoint) -> Bool? {
        guard faceContext.device == .pad || faceContext.device == .compactPad,
              tracked.mode == .typing, tracked.keyView?.key.secondary != nil else { return nil }
        let dy = point.y - tracked.start.y
        return abs(point.x - tracked.start.x) < metrics.keyHeight * 0.6 ? dy > metrics.keyHeight * 0.35 : nil
    }

    private func scheduleHold(for tracked: TrackedTouch) {
        guard let key = tracked.keyView?.key, tracked.mode == .typing else { return }
        let isSpace = key.action == .space
        guard isSpace || key.alternates.count > 1 else { return }
        tracked.hold = Timer.scheduledTimer(withTimeInterval: isSpace ? 0.4 : 0.45, repeats: false) { [weak self, weak tracked] _ in
            MainActor.assumeIsolated {
                guard let self, let tracked, tracked.mode == .typing, let view = tracked.keyView else { return }
                if isSpace {
                    tracked.mode = .trackpad
                    view.isPressed = false
                    self.setLabelsVisible(false)
                    self.onEvent(.trackpad(active: true))
                } else {
                    tracked.mode = .alternates
                    view.isPressed = true
                    self.callout.hide()
                    let shown = view.key.alternates.map(self.displayed)
                    let base = self.displayed(self.text(for: view.key, flicked: false) ?? "")
                    self.alternates.show(shown, base: base, over: view.frame, in: self.drawableBounds, metrics: self.metrics, theme: self.theme)
                }
            }
        }
    }

    private func setLabelsVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.keyViews.forEach { $0.showsLabel = visible }
        }
    }
}
