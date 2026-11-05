/// A tool that opens over the bar: its results on top and a search field under them, which the keys type into while
/// it's open (docs/design.md, "Panels").
public enum Panel: Hashable, Sendable, CaseIterable {
    case emoji
    case gif
    case clipboard
}
