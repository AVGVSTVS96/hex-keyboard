/// How a dictation is written. As Said types what the voice model wrote, "um" and "uh" included; the others are Wispr
/// Flow's styles, which leave out "um" and "uh" and change only capitals and periods, never your words.
public enum DictationStyle: String, CaseIterable, Sendable {
    case asSaid
    /// Every sentence capitalized and ended.
    case formal
    /// Capitalized, without the last period.
    case casual
    /// Without the capitals that only start a sentence or spell "I", and without the last period.
    case veryCasual

    public static let standard = DictationStyle.asSaid

    /// What you said, in this style. The lexicon tells a sentence's ordinary first word ("So") from a name ("Cheryl").
    public func written(_ heard: String, lexicon: Lexicon) -> String {
        if self == .asSaid { return heard }
        var text = Self.withoutFillers(Array(heard))
        switch self {
        case .asSaid: break
        case .formal:
            for start in Self.sentenceStarts(in: text) where text[start].isLowercase {
                text[start] = Character(text[start].uppercased())
            }
            if let last = text.last, last.isLetter || last.isNumber { text.append(".") }
        case .casual:
            Self.dropLastPeriod(&text)
        case .veryCasual:
            for start in Self.sentenceStarts(in: text) {
                let word = String(text[start...].prefix(while: Words.isWordCharacter))
                if word.dropFirst() == word.lowercased().dropFirst(), lexicon.canonical(word) == word.lowercased() {
                    text[start] = Character(text[start].lowercased())
                }
            }
            for word in Words.ranges(in: text) where Self.spellsI(text[word]) {
                text[word.lowerBound] = "i"
            }
            Self.dropLastPeriod(&text)
        }
        return String(text)
    }

    /// "um", "uh", "uhm", "erm" and "hmm", however long they're drawn out, as whole words written lowercase or
    /// capitalized, with the comma after them. A capital passes to the next word, and "uh-huh" stays.
    static func withoutFillers(_ text: [Character]) -> [Character] {
        var text = text
        while let filler = Words.ranges(in: text).first(where: { isFiller(text, $0) }) {
            var start = filler.lowerBound
            var end = filler.upperBound
            while end < text.count, text[end] == "," || text[end] == "…" || text[end] == "." && text[end...].starts(with: "...") {
                end += text[end] == "." ? 3 : 1
            }
            while end < text.count, text[end] == " " { end += 1 }
            let wordFollows = end < text.count && !TypingEngine.sentenceEnders.contains(text[end]) && !",;:".contains(text[end])
            if !wordFollows {
                while start > 0, text[start - 1] == " " { start -= 1 }
                if start > 0, text[start - 1] == ",", end < text.count, TypingEngine.sentenceEnders.contains(text[end]) { start -= 1 }
            }
            if wordFollows, text[filler.lowerBound].isUppercase, text[end].isLowercase {
                text[end] = Character(text[end].uppercased())
            }
            text.removeSubrange(start ..< end)
        }
        return text.contains { $0.isLetter || $0.isNumber } ? text : []
    }

    private static func isFiller(_ text: [Character], _ word: Range<Int>) -> Bool {
        let glued = word.upperBound < text.count && text[word.upperBound] == "-"
            || word.lowerBound > 0 && text[word.lowerBound - 1] == "-"
        guard !glued, text[word].dropFirst().allSatisfy(\.isLowercase) else { return false }
        var drawn: [Character] = []
        for letter in text[word].map({ Character($0.lowercased()) }) where letter != drawn.last { drawn.append(letter) }
        return ["um", "uh", "uhm", "erm", "hm"].contains(String(drawn))
    }

    private static func spellsI(_ word: ArraySlice<Character>) -> Bool {
        guard word.first == "I" else { return false }
        let rest = word.dropFirst()
        return rest.isEmpty || ["'", "’"].contains(rest.first) && ["m", "ll", "ve", "d"].contains(String(rest.dropFirst()))
    }

    private static func dropLastPeriod(_ text: inout [Character]) {
        if text.last == ".", text.dropLast().last != "." { text.removeLast() }
    }

    /// Where each sentence's first word starts: the text's start, or after a period, question mark, exclamation mark or
    /// line break, past any spaces and openers.
    private static func sentenceStarts(in text: [Character]) -> [Int] {
        var starts: [Int] = []
        var expecting = true
        for (at, character) in text.enumerated() {
            if expecting, Words.isWordCharacter(character) {
                if character.isLetter { starts.append(at) }
                expecting = false
            } else if character.isNewline || TypingEngine.sentenceEnders.contains(character) && (at + 1 == text.count || text[at + 1].isWhitespace) {
                expecting = true
            } else if expecting, !character.isWhitespace, !Words.openers.contains(character) {
                expecting = false
            }
        }
        return starts
    }
}
