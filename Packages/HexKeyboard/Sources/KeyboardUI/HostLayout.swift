import KeyboardCore
import UIKit

/// The text laid out as the field the keyboard types into likely lays it out. iOS never tells a keyboard where its
/// host wraps lines, only the text around the caret, so this wraps it in the body font at the reader's text size, as
/// wide as the field likely is; where the host wraps differently, a move up or down lands a few letters off.
struct HostLayout: LineLayout {
    var width: CGFloat
    var font = Self.font

    /// Chat apps put buttons beside their field (Messages: + on the left, the mic inside on the right); other apps run
    /// text nearly edge to edge.
    init(keyboardWidth: CGFloat, host: String?) {
        width = keyboardWidth - (host.map(Self.chatApps.contains) == true ? 120 : 40)
    }

    private static let chatApps: Set = [
        "com.apple.MobileSMS", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp", "org.whispersystems.signal",
        "com.tinyspeck.chatlyio", "com.hammerandchisel.discord", "com.facebook.Messenger", "com.burbn.instagram",
    ]

    static var font: UIFont { .preferredFont(forTextStyle: .body) }
    /// How far a finger on the space bar moves for the caret to move a line, as far as a line is tall.
    static var lineHeight: CGFloat { font.lineHeight }

    func carets(in paragraph: String) -> [Caret] {
        let storage = NSTextStorage(string: paragraph, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var lines: [NSRange] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, glyphs, _ in
            lines.append(glyphs)
        }
        var carets: [Caret] = [], line = 0, offset = 0
        for character in paragraph {
            let glyph = manager.glyphIndexForCharacter(at: offset)
            while line < lines.count - 1, glyph >= NSMaxRange(lines[line]) { line += 1 }
            carets.append(Caret(line: line, x: manager.location(forGlyphAt: glyph).x))
            offset += character.utf16.count
        }
        let last = max(lines.count - 1, 0)
        carets.append(Caret(line: last, x: lines.isEmpty ? 0 : manager.lineFragmentUsedRect(forGlyphAt: lines[last].location, effectiveRange: nil).maxX))
        return carets
    }
}
