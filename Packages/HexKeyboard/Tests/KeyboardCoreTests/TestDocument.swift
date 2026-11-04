@testable import KeyboardCore

class TestDocument: TextDocument {
    var text: String
    var cursor: Int
    /// How many characters after the cursor are selected.
    var selection = 0

    init(_ text: String = "") {
        self.text = text
        self.cursor = text.count
    }

    var textBeforeInput: String? { String(text.prefix(cursor)) }
    var textAfterInput: String? { String(text.dropFirst(cursor + selection)) }
    var selectedText: String? { String(text.dropFirst(cursor).prefix(selection)) }

    func select(_ word: String) {
        cursor = text.distance(from: text.startIndex, to: text.range(of: word)!.lowerBound)
        selection = word.count
    }

    func insert(_ value: String) {
        deleteSelection()
        let index = text.index(text.startIndex, offsetBy: cursor)
        text.insert(contentsOf: value, at: index)
        cursor += value.count
    }

    func deleteBackward(_ count: Int) {
        let count = selection > 0 ? count - 1 : count
        deleteSelection()
        let removed = min(count, cursor)
        let end = text.index(text.startIndex, offsetBy: cursor)
        text.removeSubrange(text.index(end, offsetBy: -removed)..<end)
        cursor -= removed
    }

    func moveCursor(by offset: Int) {
        cursor = min(max(cursor + selection + offset, 0), text.count)
        selection = 0
    }

    private func deleteSelection() {
        let start = text.index(text.startIndex, offsetBy: cursor)
        text.removeSubrange(start..<text.index(start, offsetBy: selection))
        selection = 0
    }
}

extension TypingEngine {
    mutating func type(_ string: String, in document: some TextDocument) {
        for character in string {
            perform(character == " " ? .space : .character(String(character).lowercased()), in: document)
        }
    }
}
