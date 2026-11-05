import UIKit

/// How loud the app heard you, from its published level, 0 for quiet to 1 for loud.
func loudness(_ level: Float) -> CGFloat {
    CGFloat(min(max((20 * log10(max(level, 1e-6)) + 55) / 40, 0), 1))
}

/// Motion that follows your voice, a quick spring with no bounce, so each level carries on from the last mid-flight.
func follow(duration: TimeInterval = 0.18, _ changes: @escaping () -> Void) {
    UIView.animate(springDuration: duration, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
}

/// A change of state, slower than following your voice, and still interruptible.
func settle(bounce: CGFloat = 0, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    UIView.animate(springDuration: 0.35, bounce: bounce, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes, completion: completion)
}

/// The mic growing into the recording, with a little give, or shrinking back without: the capsule, its color, its
/// glyphs and the cancel button it lets out all move on this one spring, so they never drift apart.
func morph(growing: Bool, _ changes: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
    UIView.animate(
        springDuration: growing ? 0.45 : 0.35, bounce: growing ? 0.12 : 0, options: [.beginFromCurrentState, .allowUserInteraction],
        animations: changes, completion: completion
    )
}
