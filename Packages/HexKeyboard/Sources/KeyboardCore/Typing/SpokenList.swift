/// A list you speak, written as one, as Wispr Flow does: "my goals are one, finish the report, two, send it" becomes
/// "my goals are:", then "1. finish the report" and "2. send it" on lines of their own. A marker is a number, a digit
/// or an ordinal ("first", "secondly", "number three") with a comma, colon or period after it, as Parakeet writes the
/// pause you make there, and the markers count up from one. Two markers make a list only where a sentence or clause
/// starts with the first, so "I have one, maybe two, cats" stays a sentence; three always do. The last item runs to the
/// end of its sentence, and what follows starts a new line.
enum SpokenList {
    static func written(_ text: [Character]) -> [Character] {
        guard let list = first(in: text) else { return text }
        var intro = Array(text[..<list.markers[0].lowerBound])
        while intro.last == " " { intro.removeLast() }
        if intro.last == "," || intro.last == ";" { intro.removeLast() }
        if let last = intro.last, Words.isWordCharacter(last) { intro.append(":") }

        var lines: [[Character]] = intro.isEmpty ? [] : [intro]
        for (index, item) in list.items.enumerated() {
            lines.append(Array("\(index + 1). ") + item)
        }
        var rest = Array(text[list.end...])
        while rest.first == " " || rest.first?.isNewline == true { rest.removeFirst() }
        if !rest.isEmpty { lines.append(written(rest)) }
        return Array(lines.joined(separator: "\n"))
    }

    private struct Found {
        /// Each marker's word, or "number" and its word.
        var markers: [Range<Int>]
        var items: [[Character]]
        /// Where the text after the last item starts.
        var end: Int
    }

    private static func first(in text: [Character]) -> Found? {
        let words = Words.ranges(in: text)
        let markers = words.indices.compactMap { index in marker(text, words, index).map { (index: index, value: $0.value, ordinal: $0.ordinal) } }
        for (position, start) in markers.enumerated() where start.value == 1 {
            var chain = [start]
            for next in markers[(position + 1)...] where next.ordinal == start.ordinal {
                guard next.value == chain.count + 1 else { break }
                let between = text[words[chain.last!.index].upperBound ..< span(text, words, next.index).lowerBound]
                guard between.contains(where: \.isLetter) || between.contains(where: \.isNumber), !between.contains(where: \.isNewline) else { break }
                chain.append(next)
            }
            let spans = chain.map { span(text, words, $0.index) }
            guard chain.count >= 3 || chain.count == 2 && opensClause(text, at: spans[0].lowerBound) else { continue }
            var items: [[Character]] = []
            for (index, marker) in spans.enumerated() {
                let from = afterMarker(text, marker)
                let to = index + 1 < spans.count ? spans[index + 1].lowerBound : lastItemEnd(text, from: from)
                items.append(trimmed(Array(text[from ..< to])))
            }
            guard !items.contains(where: \.isEmpty) else { continue }
            let last = lastItemEnd(text, from: afterMarker(text, spans.last!))
            let end = last < text.count && ".!?".contains(text[last]) ? last + 1 : last
            if end > last { items[items.count - 1] += text[last] == "." ? [] : [text[last]] }
            return Found(markers: spans, items: items, end: end)
        }
        return nil
    }

    private static let numbers = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]

    /// The word's place in a list, if it's a marker: followed by a comma, colon or period, and not part of a longer
    /// number such as "twenty-one".
    private static func marker(_ text: [Character], _ words: [Range<Int>], _ index: Int) -> (value: Int, ordinal: Bool)? {
        let word = words[index]
        guard word.upperBound < text.count, ",:.".contains(text[word.upperBound]),
              word.upperBound + 1 == text.count || text[word.upperBound + 1] == " " || text[word.upperBound + 1].isNewline,
              word.lowerBound == 0 || text[word.lowerBound - 1] != "-" else { return nil }
        var spelled = String(text[word]).lowercased()
        if spelled.hasSuffix("ly") { spelled.removeLast(2) }
        if let number = numbers.firstIndex(of: spelled) { return (number + 1, false) }
        if let number = Int(spelled), (1 ... 10).contains(number) { return (number, false) }
        if let ordinal = ordinals.firstIndex(of: spelled) { return (ordinal + 1, true) }
        return nil
    }

    /// The marker's word, from "number" when it's said before it.
    private static func span(_ text: [Character], _ words: [Range<Int>], _ index: Int) -> Range<Int> {
        guard index > 0, String(text[words[index - 1]]).lowercased() == "number",
              text[words[index - 1].upperBound ..< words[index].lowerBound].allSatisfy({ $0 == " " }) else { return words[index] }
        return words[index - 1].lowerBound ..< words[index].upperBound
    }

    private static func afterMarker(_ text: [Character], _ marker: Range<Int>) -> Int {
        var at = marker.upperBound + 1
        while at < text.count, text[at] == " " { at += 1 }
        return min(at, text.count)
    }

    private static func opensClause(_ text: [Character], at: Int) -> Bool {
        let before = text[..<at].last { $0 != " " }
        return before.map { $0.isNewline || ".,:;!?".contains($0) } ?? true
    }

    /// The end of the sentence the last item starts: its period, question or exclamation mark, or a line break.
    private static func lastItemEnd(_ text: [Character], from: Int) -> Int {
        var at = from
        while at < text.count {
            if text[at].isNewline { return at }
            if ".!?".contains(text[at]), at + 1 == text.count || text[at + 1] == " " || text[at + 1].isNewline { return at }
            at += 1
        }
        return at
    }

    /// An item without the spaces, commas or "and" that lead into the next one.
    private static func trimmed(_ item: [Character]) -> [Character] {
        var item = item
        while let last = item.last, last == " " || ",;.".contains(last) { item.removeLast() }
        for joiner in [" and", " or"] where item.count > joiner.count && String(item.suffix(joiner.count)).lowercased() == joiner {
            item.removeLast(joiner.count)
            while let last = item.last, last == " " || ",;".contains(last) { item.removeLast() }
        }
        return item
    }
}
