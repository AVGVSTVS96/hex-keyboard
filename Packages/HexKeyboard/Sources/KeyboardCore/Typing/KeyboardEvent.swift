public enum KeyboardEvent: Hashable, Sendable {
    case down(Key, tapCount: Int)
    case up(Key)
    case type(Key, Tap)
    case slide(String)
    /// A finger that went over the letters without lifting, as a word.
    case swipe([SwipePoint])
    case trigger(Key)
    case cursor(offset: Int)
    /// Moves the caret down that many lines, up when negative.
    case cursorLines(Int)
    case oneHanded(OneHanded)
    /// A hand picked from the layer key's menu. The key switched layers as it went down, so the letters come back.
    case pick(OneHanded)
    /// The open Duo's keys in two halves, or back to one, picked from a menu, so the letters come back as with `pick`.
    case split(Bool)
    /// Hex's settings picked from a menu: the app opens on them, and the letters come back for when you return.
    case settings
    /// The layout in use, picked from the layer key's menu where no other applies: nothing changes, and the letters
    /// come back, so letting go without sliding is as if the key had only been tapped.
    case keep
    /// The next keyboard picked from a menu, since an iPhone's keys carry no globe. The letters come back for your return.
    case nextKeyboard
    /// Opens a panel over the bar, or closes it with nil. While one is open, the keys type into its search.
    case panel(Panel?)
    /// An emoji picked in the emoji panel, with its untoned version when it was picked among skin tones.
    case emoji(String, base: String?)
    /// Text from the clipboard panel, typed as it is.
    case paste(String)
    /// Text that dictation heard in its style, and as the model wrote it with the person's vocabulary (`plain`, which
    /// the field's reading takes: `DictationReading`), the same when nil. One with its transcript's `id` is followed
    /// until its field is sent or left, for what it became (`TypingEngine.takeDictations`).
    case dictated(String, plain: String? = nil, id: String? = nil)
}
