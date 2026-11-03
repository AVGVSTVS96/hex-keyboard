import UIKit

/// A scroll view of buttons that still scrolls when a drag starts on one: UIKit's own never cancels a control's touch,
/// so rows that fill it would never let it move.
final class ButtonScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        [topEdgeEffect, bottomEdgeEffect, leftEdgeEffect, rightEdgeEffect].forEach { $0.isHidden = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}
