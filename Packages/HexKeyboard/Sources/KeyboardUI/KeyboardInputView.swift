import UIKit

final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    /// iOS hit-tests a third-party keyboard by its pixels: a touch on a fully transparent pixel never reaches the
    /// extension, so without a fill every gap between keys, the strip above the top row and the suggestion bar's
    /// empty parts would swallow taps (measured in the simulator, `FirstTapTests`). This fill is too faint to show.
    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        backgroundColor = UIColor(white: 0, alpha: 0.001)
    }

    required init?(coder: NSCoder) { fatalError() }
}
