import UIKit
import KeyboardCore

extension KeyboardView {
    final class TrackedTouch {
        enum Mode { case typing, alternates, trackpad, slide }

        weak var keyView: KeyView?
        var mode = Mode.typing
        var flicked = false
        let start: CGPoint
        var point: CGPoint
        var lastCursorX: CGFloat
        var hold: Timer?

        init(keyView: KeyView, start: CGPoint) {
            self.keyView = keyView
            self.start = start
            self.point = start
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
            tracked.point = point
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
            tracked.point = touch.location(in: self)
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
            if commit, let text = alternates.selected { onEvent(.type(view.key, text: text, at: tracked.point)) }
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
                onEvent(.type(view.key, text: text, at: tracked.point))
            } else if view.key.action == .space {
                onEvent(.type(view.key, text: " ", at: tracked.point))
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
                    view.isPressed = KeyboardStyle.current.dimsKeyUnderAccents
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
