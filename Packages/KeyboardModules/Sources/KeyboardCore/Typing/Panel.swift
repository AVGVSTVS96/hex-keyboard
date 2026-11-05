/// A tool that opens over the bar: its results on top and a search field under them, which the keys type into while
/// it's open (docs/design.md, "Panels").
public enum Panel: Hashable, Sendable, CaseIterable {
    case emoji
    case gif
    case clipboard
    /// What you dictated, from the clipboard's tools, beside the clipboard's history.
    case transcripts

    /// The panels with a tool of their own in the bar; Transcripts opens from the clipboard's.
    public static let tools: [Panel] = [.emoji, .gif, .clipboard]
}
