import UIKit

/// How big the field the keyboard types into likely draws its text, so the space bar trackpad moves the caret about as
/// far as the finger moves. iOS tells a keyboard nothing of the field's font, so this takes the body font most fields use.
public enum HostText {
    static var font: UIFont { .preferredFont(forTextStyle: .body) }

    /// How far a finger on the space bar moves for the caret to cross a character, as wide as the character is, as
    /// Apple's trackpad keeps the caret under the finger. A line break is as wide as a space, and so is a character the
    /// keyboard can't see (nil): hosts show only the caret's paragraph, so that is most often the line break at its edge.
    public static func width(of character: Character?) -> CGFloat {
        let shown = character.map { $0.isNewline ? " " : String($0) } ?? " "
        return (shown as NSString).size(withAttributes: [.font: font]).width
    }
}
