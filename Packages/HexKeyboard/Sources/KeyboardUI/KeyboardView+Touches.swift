import UIKit
import KeyboardCore

extension KeyboardView {
    final class TrackedTouch {
        enum Mode { case typing, alternates, trackpad, slide, menu, swipe }

        var key: Key
        weak var keyView: KeyView?
        var mode = Mode.typing
        var flicked = false
        let start: CGPoint
        var point: CGPoint
        var lastCursor: CGPoint
        var hold: Timer?
        var menuFrame: CGRect?
        let began: TimeInterval
        let swipeReach: CGFloat
        var path: [SwipePoint]

        init(keyView: KeyView, start: CGPoint, at time: TimeInterval, swipes: Bool) {
            self.key = keyView.key
            self.keyView = keyView
            self.start = start
            self.point = start
            self.lastCursor = start
            self.began = time
            self.swipeReach = swipes ? keyView.frame.width * KeyboardView.swipeDistance : .infinity
            self.path = [SwipePoint(x: start.x, y: start.y, time: 0)]
        }

        func follow(_ touch: UITouch, in view: UIView, event: UIEvent?) {
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                let at = sample.location(in: view)
                path.append(SwipePoint(x: at.x, y: at.y, time: sample.timestamp - began))
            }
        }

        /// The path with its times, which the simulator's synthesized touches lack: every sample but the last carries the
        /// time the finger went down, so the path is timed as one sampled at 120 Hz.
        var timed: [SwipePoint] {
            guard path.count > 2, path.dropLast().allSatisfy({ $0.time == 0 }) else { return path }
            return path.enumerated().map { SwipePoint(x: $1.x, y: $1.y, time: Double($0) / 120) }
        }
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("began", touches, event, since: start) }
        for touch in touches.inOrder {
            rollOver()
            let point = touch.location(in: self)
            guard let view = keyView(at: point) else { continue }
            let tracked = TrackedTouch(keyView: view, start: point, at: touch.timestamp, swipes: slidesToType && startsSwipe(view.key))
            self.tracked[ObjectIdentifier(touch)] = tracked
            if menu.keys.contains(view.key), !menu.items.isEmpty { tracked.menuFrame = view.frame }
            press(view, tracked: tracked)
            onEvent(.down(view.key, tapCount: touch.tapCount))
            if case .layer = view.key.action { tracked.mode = .slide }
            scheduleHold(for: tracked)
        }
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("moved", touches, event, since: start) }
        for touch in touches {
            guard let tracked = tracked[ObjectIdentifier(touch)] else { continue }
            let point = touch.location(in: self)
            tracked.point = point
            switch tracked.mode {
            case .alternates, .menu:
                alternates.track(point)
            case .trackpad:
                while true {
                    let step = point.x > tracked.lastCursor.x ? 1 : -1, width = advance(step)
                    guard abs(point.x - tracked.lastCursor.x) >= width else { break }
                    tracked.lastCursor.x += CGFloat(step) * width
                    onEvent(.cursor(offset: step))
                }
                let line = HostLayout.lineHeight
                let lines = Int((point.y - tracked.lastCursor.y) / line)
                if lines != 0 {
                    tracked.lastCursor.y += CGFloat(lines) * line
                    onEvent(.cursorLines(lines))
                }
            case .swipe:
                let drawn = tracked.path.count
                tracked.follow(touch, in: self, event: event)
                trail.add(tracked.path[drawn...])
            case .typing, .slide:
                if tracked.swipeReach.isFinite {
                    tracked.follow(touch, in: self, event: event)
                    if hypot(point.x - tracked.start.x, point.y - tracked.start.y) >= tracked.swipeReach { beginSwipe(tracked) }
                    if tracked.mode == .swipe { continue }
                }
                if let flick = flickTarget(tracked, point) {
                    tracked.hold?.invalidate()
                    tracked.flicked = flick
                    tracked.keyView?.isFlicked = flick
                    continue
                }
                if let frame = tracked.menuFrame, !frame.contains(point) {
                    tracked.menuFrame = nil
                    tracked.hold?.invalidate()
                }
                guard let view = keyView(at: point), view.key != tracked.key,
                      tracked.mode == .slide || (view.key.isInput && tracked.key.isInput) else { continue }
                tracked.keyView?.isPressed = false
                tracked.key = view.key
                tracked.keyView = view
                press(view, tracked: tracked)
                guard tracked.menuFrame == nil else { continue }
                tracked.hold?.invalidate()
                scheduleHold(for: tracked)
            }
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("ended", touches, event, since: start) }
        for touch in touches.inOrder {
            guard let tracked = tracked.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            tracked.point = touch.location(in: self)
            finish(tracked, commit: true)
        }
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let start = CACurrentMediaTime()
        defer { TouchTrace.shared.record("cancelled", touches, event, since: start) }
        for touch in touches {
            guard let tracked = tracked.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finish(tracked, commit: false)
        }
    }

    private func rollOver() {
        for (id, other) in tracked where other.mode == .swipe || other.mode == .typing && other.key.isInput {
            tracked.removeValue(forKey: id)
            finish(other, commit: true)
        }
    }

    private func finish(_ tracked: TrackedTouch, commit: Bool) {
        tracked.hold?.invalidate()
        callout.hide()
        let key = tracked.key
        tracked.keyView?.isPressed = false
        tracked.keyView?.isFlicked = false
        defer { onEvent(.up(key)) }

        switch tracked.mode {
        case .alternates:
            if commit, key.alternates.indices.contains(alternates.selection) {
                onEvent(.type(key, tap(tracked, displayed(key.alternates[alternates.selection]))))
            }
            alternates.hide()
        case .menu:
            if commit, menu.items.indices.contains(alternates.selection) { onEvent(menu.items[alternates.selection]) }
            alternates.hide()
        case .trackpad:
            setLabelsVisible(true)
        case .slide:
            if commit, key.isInput, let text = text(for: key, flicked: tracked.flicked) {
                onEvent(.slide(text))
            }
        case .swipe:
            if commit { onEvent(.swipe(tracked.timed)) }
        case .typing:
            guard commit else { return }
            if let text = text(for: key, flicked: tracked.flicked) {
                onEvent(.type(key, tap(tracked, text)))
            } else if key.action == .space {
                onEvent(.type(key, tap(tracked, " ")))
            } else {
                onEvent(.trigger(key))
            }
        }
    }

    private func startsSwipe(_ key: Key) -> Bool {
        faceContext.layer == .letters && key.label?.first?.isLetter == true
    }

    private func beginSwipe(_ tracked: TrackedTouch) {
        tracked.mode = .swipe
        tracked.hold?.invalidate()
        callout.hide()
        tracked.keyView?.isPressed = false
        tracked.keyView?.isFlicked = false
        trail.begin(tracked.path[...])
    }

    private func tap(_ tracked: TrackedTouch, _ text: String) -> Tap {
        Tap(x: tracked.point.x, y: tracked.point.y, key: text)
    }

    private func press(_ view: KeyView, tracked: TrackedTouch) {
        view.isPressed = !(showsCallouts && characterPreview == .attached && view.key.text(shifted: false) != nil)
        show(tracked)
    }

    private func show(_ tracked: TrackedTouch) {
        guard showsCallouts, tracked.mode != .alternates, let view = tracked.keyView,
              let text = text(for: view.key, flicked: tracked.flicked) else { return callout.hide() }
        callout.show(displayed(text), over: view.frame, in: drawableBounds, metrics: keyMetrics, theme: theme, detached: characterPreview == .detached)
    }

    private func text(for key: Key, flicked: Bool) -> String? {
        key.text(shifted: faceContext.shift.isUppercase, flicked: flicked)
    }

    private func displayed(_ text: String) -> String {
        faceContext.shift.isUppercase ? text.uppercased() : text
    }

    private func flickTarget(_ tracked: TrackedTouch, _ point: CGPoint) -> Bool? {
        guard faceContext.device == .pad || faceContext.device == .compactPad,
              tracked.mode == .typing, tracked.key.secondary != nil else { return nil }
        let dy = point.y - tracked.start.y
        return abs(point.x - tracked.start.x) < metrics.keyHeight * 0.6 ? dy > metrics.keyHeight * 0.35 : nil
    }

    private func scheduleHold(for tracked: TrackedTouch) {
        let key = tracked.key
        if tracked.menuFrame != nil { return scheduleMenu(for: tracked) }
        guard tracked.mode == .typing else { return }
        let isSpace = key.action == .space
        guard isSpace || key.alternates.count > 1 else { return }
        tracked.hold = Timer.scheduledTimer(withTimeInterval: isSpace ? 0.4 : 0.45, repeats: false) { [weak self, weak tracked] _ in // timer: long-press
            MainActor.assumeIsolated {
                guard let self, let tracked, tracked.mode == .typing, let view = tracked.keyView else { return }
                if isSpace {
                    tracked.mode = .trackpad
                    tracked.lastCursor = tracked.point
                    view.isPressed = false
                    self.setLabelsVisible(false)
                } else {
                    tracked.mode = .alternates
                    view.isPressed = KeyboardStyle.current.dimsKeyUnderAccents
                    self.callout.hide()
                    let shown = view.key.alternates.map(self.displayed)
                    let base = self.displayed(self.text(for: view.key, flicked: false) ?? "")
                    self.alternates.show(shown, selected: shown.firstIndex(of: base) ?? 0, over: view.frame, in: self.drawableBounds, metrics: self.keyMetrics, theme: self.theme)
                }
            }
        }
    }

    private func scheduleMenu(for tracked: TrackedTouch) {
        tracked.hold = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak tracked] _ in // timer: long-press
            MainActor.assumeIsolated {
                guard let self, let tracked, tracked.mode == .slide || tracked.mode == .typing, let frame = tracked.menuFrame else { return }
                tracked.mode = .menu
                self.callout.hide()
                let items = self.menu.items
                self.alternates.show(symbols: items.map(\.symbol), selected: self.menu.current.flatMap(items.firstIndex) ?? 0, over: frame, in: self.drawableBounds, metrics: self.keyMetrics, theme: self.theme)
            }
        }
    }

    private func setLabelsVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.keyViews.forEach { $0.showsLabel = visible }
        }
    }
}

extension KeyboardEvent {
    /// How the layer menu and the bar's More button show a pick.
    public var symbol: String {
        switch self {
        case .pick(.left): "keyboard.onehanded.left"
        case .pick(.right): "keyboard.onehanded.right"
        case .split(true): "rectangle.split.2x1"
        case .settings: "gearshape"
        case .nextKeyboard: "globe"
        default: "keyboard"
        }
    }

    public var title: String {
        switch self {
        case .pick(.left): "Left"
        case .pick(.right): "Right"
        case .split(true): "Split"
        case .settings: "iikb Settings"
        case .nextKeyboard: "Next Keyboard"
        default: "Full"
        }
    }
}

private extension Set<UITouch> {
    var inOrder: [UITouch] { sorted { $0.timestamp < $1.timestamp } }
}
