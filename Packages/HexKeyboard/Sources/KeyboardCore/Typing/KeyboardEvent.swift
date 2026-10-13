public enum KeyboardEvent: Hashable, Sendable {
    case down(Key, tapCount: Int)
    case up(Key)
    case type(Key, Tap)
    case slide(String)
    case trigger(Key)
    case cursor(offset: Int)
    case oneHanded(OneHanded)
    /// An item picked from the layer key's menu. The key switched layers as it went down, so the letters come back.
    case pick(MenuItem)
    /// An emoji tapped on the emoji keyboard, with its untoned key when it was picked among skin tones.
    case emoji(String, base: String?)
    /// The emoji keyboard's ABC key.
    case closeEmoji
    /// Text that dictation heard.
    case dictated(String)
}
