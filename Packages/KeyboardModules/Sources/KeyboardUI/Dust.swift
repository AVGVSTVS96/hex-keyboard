import UIKit

/// Something thrown away, breaking into dust as a deleted message does in Telegram: a picture of it cut into specks
/// that blow off up and away, starting from the side you tapped and sweeping across.
final class Dust: UIView {
    private let specks: [(layer: CALayer, distance: CGFloat)]

    /// `area` of `view`, in its coordinates, starting from `origin`, a point on `view`'s x axis.
    init?(of view: UIView, in area: CGRect, from origin: CGFloat) {
        let scale = view.traitCollection.displayScale
        let width = Int((area.width * scale).rounded(.up)), height = Int((area.height * scale).rounded(.up))
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)
        UIGraphicsPushContext(context)
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        UIGraphicsPopContext()
        guard let picture = context.makeImage(), let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        let side = max(1.5, (area.width * area.height / 2400).squareRoot())
        let reach = max(abs(origin - area.minX), abs(area.maxX - origin), 1)
        var specks: [(CALayer, CGFloat)] = []
        var y: CGFloat = 0
        while y < area.height {
            var x: CGFloat = 0
            while x < area.width {
                let tile = CGRect(x: x, y: y, width: min(side, area.width - x), height: min(side, area.height - y))
                let px = min(Int((tile.midX * scale)), width - 1), py = min(Int((tile.midY * scale)), height - 1)
                if pixels[(py * width + px) * 4 + 3] > 24 {
                    let speck = CALayer()
                    speck.contents = picture
                    speck.contentsScale = scale
                    speck.contentsRect = CGRect(x: tile.minX / area.width, y: tile.minY / area.height, width: tile.width / area.width, height: tile.height / area.height)
                    speck.frame = tile
                    specks.append((speck, abs(area.minX + tile.midX - origin) / reach))
                }
                x += side
            }
            y += side
        }
        self.specks = specks
        super.init(frame: area)
        isUserInteractionEnabled = false
        specks.forEach { layer.addSublayer($0.0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Blows the specks away, then removes itself and calls `done`. With Reduce Motion it fades instead.
    func play(away direction: CGFloat, done: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.removeFromSuperview()
            done()
        }
        if UIAccessibility.isReduceMotionEnabled {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.25
            layer.opacity = 0
            layer.add(fade, forKey: "fade")
            CATransaction.commit()
            return
        }
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        for (speck, distance) in specks {
            let start = speck.position
            let drift = CGPoint(x: direction * .random(in: 2...30), y: -.random(in: 6...36))
            let lift = CGPoint(x: start.x + drift.x * 0.35, y: start.y + drift.y * 0.9)
            let path = UIBezierPath()
            path.move(to: start)
            path.addQuadCurve(to: CGPoint(x: start.x + drift.x, y: start.y + drift.y), controlPoint: lift)

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path.cgPath
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.35, 1)
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.toValue = CGFloat.random(in: 0.2...0.7)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)

            let blow = CAAnimationGroup()
            blow.animations = [move, shrink, fade]
            blow.duration = .random(in: 0.5...0.8)
            blow.beginTime = now + distance * 0.32 + .random(in: 0...0.07)
            blow.fillMode = .backwards
            speck.opacity = 0
            speck.add(blow, forKey: "blow")
        }
        CATransaction.commit()
    }
}
