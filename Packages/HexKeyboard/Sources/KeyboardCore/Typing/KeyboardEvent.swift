public enum KeyboardEvent: Hashable, Sendable {
    case down(Key, tapCount: Int)
    case up(Key)
    case type(Key, Tap)
    case slide(String)
    case trigger(Key)
    case cursor(offset: Int)
    case oneHanded(OneHanded)
    /// A hand picked from the layer key's menu. The key switched layers as it went down, so the letters come back.
    case pick(OneHanded)
    /// Opens a panel over the bar, or closes it with nil. While one is open, the keys type into its search.
    case panel(Panel?)
    /// An emoji picked in the emoji panel, with its untoned version when it was picked among skin tones.
    case emoji(String, base: String?)
    /// Text from the clipboard panel, typed as it is.
    case paste(String)
    /// Text that dictation heard.
    case dictated(String)
}
