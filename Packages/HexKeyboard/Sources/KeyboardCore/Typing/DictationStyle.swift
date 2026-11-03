/// How a dictation ends, in Wispr Flow's styles. Your words are kept, um and uh too unless you leave them out, and
/// capitals follow Auto-Capitalization, as typing's do (`TypingEngine.fitted`).
public enum DictationStyle: String, CaseIterable, Sendable {
    /// Ended with a period.
    case formal
    /// Without the last period.
    case casual

    public static let standard = DictationStyle.formal

    /// What you said, in this style, with um and uh or without them.
    public func written(_ heard: String, keepingFillers: Bool) -> String {
        var text = keepingFillers ? Array(heard) : Self.withoutFillers(Array(heard))
        switch self {
        case .formal:
            if let last = text.last, last.isLetter || last.isNumber { text.append(".") }
        case .casual:
            if text.last == ".", text.dropLast().last != "." { text.removeLast() }
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
}
