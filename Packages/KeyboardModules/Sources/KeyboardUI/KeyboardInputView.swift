import UIKit

public final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }

    /// iOS drops touches on fully transparent pixels of a third-party keyboard, so without this fill, too faint to
    /// show, taps between keys never arrive (`FirstTapTests`).
    override public init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        backgroundColor = UIColor(white: 0, alpha: 0.001)
    }

    required init?(coder: NSCoder) { fatalError() }
}
