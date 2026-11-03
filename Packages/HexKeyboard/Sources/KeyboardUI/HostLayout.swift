import KeyboardCore
import UIKit

/// Where the field the keyboard types into wraps its text, as far as a keyboard can know: iOS gives it the text around
/// the caret, never the field's width. Every field fits the screen, so this wraps the text in the body font as wide as
/// the screen within the system's margins; in a narrower field a move up or down lands a few letters off.
struct HostLayout: LineLayout {
    var width: CGFloat
    var font = Self.font

    static var font: UIFont { .preferredFont(forTextStyle: .body) }
    /// How far a finger on the space bar moves for the caret to move a line, as far as a line is tall.
    static var lineHeight: CGFloat { font.lineHeight }

    func carets(in paragraph: String) -> [Caret] {
        let storage = NSTextStorage(string: paragraph, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
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
