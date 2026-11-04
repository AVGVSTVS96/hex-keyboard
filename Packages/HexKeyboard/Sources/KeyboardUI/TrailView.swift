import UIKit
import KeyboardCore

/// The line a swipe leaves behind the finger: thin, each stretch fading as it ages, and gone a moment after the finger
/// lifts.
final class TrailView: UIView {
    var color = UIColor.white
    private var points: [(point: CGPoint, time: CFTimeInterval)] = []
    private var link: CADisplayLink?
    private static let lifetime: CFTimeInterval = 0.4
    private static let width: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) { fatalError() }

    func begin(_ samples: ArraySlice<SwipePoint>) {
        points = []
        add(samples)
    }

    func add(_ samples: ArraySlice<SwipePoint>) {
        guard !samples.isEmpty else { return }
        let now = CACurrentMediaTime()
        points += samples.map { (CGPoint(x: $0.x, y: $0.y), now) }
        if link == nil {
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick() {
        let cutoff = CACurrentMediaTime() - Self.lifetime
        points.removeAll { $0.time < cutoff }
        if points.isEmpty {
            link?.invalidate()
            link = nil
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard points.count > 1, let context = UIGraphicsGetCurrentContext() else { return }
        let now = CACurrentMediaTime()
        context.setLineWidth(Self.width)
        context.setLineCap(.round)
        for (from, to) in zip(points, points.dropFirst()) {
            let fade = max(1 - (now - to.time) / Self.lifetime, 0)
            context.setStrokeColor(color.withAlphaComponent(CGFloat(fade) * 0.9).cgColor)
            context.move(to: from.point)
            context.addLine(to: to.point)
            context.strokePath()
        }
    }
}
