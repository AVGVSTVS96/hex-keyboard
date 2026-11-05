import UIKit
import KeyboardCore

extension CGFloat {
    func rounded(scale: CGFloat) -> CGFloat { (self * scale).rounded() / scale }
}

extension CGRect {
    func rounded(scale: CGFloat) -> CGRect {
        let left = minX.rounded(scale: scale), top = minY.rounded(scale: scale)
        return CGRect(x: left, y: top, width: maxX.rounded(scale: scale) - left, height: maxY.rounded(scale: scale) - top)
    }
}

extension CGRect {
    init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
