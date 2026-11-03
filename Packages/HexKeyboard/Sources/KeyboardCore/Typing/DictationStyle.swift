/// How a dictation reads, in Wispr Flow's styles: its capitals and its punctuation. The words are `DictationEditing`'s.
public enum DictationStyle: String, CaseIterable, Hashable, Sendable {
    /// Capitals and every period.
    case formal
    /// Capitals, without the last period or the comma after an opening "so" or "also".
    case casual
    /// Casual in lowercase, names and the like kept as the lexicon spells them.
    case veryCasual
    /// Capitals, ending with an exclamation mark.
    case excited

    public static let standard = DictationStyle.formal

    /// The capitals the keyboard gives a dictation in a field that asks for `field`'s (`TypingEngine.fitted`).
    public func capitals(in field: Autocapitalization) -> Autocapitalization {
        self == .veryCasual ? .none : field
    }

    /// `text` punctuated in this style, around a list it may end on.
    func punctuated(_ text: [Character]) -> [Character] {
        var text = text
        switch self {
        case .formal:
            if let last = text.last, last.isLetter || last.isNumber { text.append(".") }
        case .casual, .veryCasual:
            if text.last == ".", text.dropLast().last != "." { text.removeLast() }
        case .excited:
            if text.last == ".", text.dropLast().last != "." { text.removeLast() }
            if let last = text.last, last.isLetter || last.isNumber { text.append("!") }
        }
        return text
    }

    /// Without the comma after a sentence's opening word, as in "So, " or "Also, ", in the casual styles.
    func openersLoosened(_ text: [Character]) -> [Character] {
        guard self == .casual || self == .veryCasual else { return text }
        var text = text
        for word in Words.ranges(in: text).reversed() where word.upperBound < text.count && text[word.upperBound] == "," {
            guard Self.openers.contains(String(text[word]).lowercased()), Self.startsSentence(text, at: word.lowerBound) else { continue }
            text.remove(at: word.upperBound)
        }
        return text
    }

    private static let openers: Set<String> = [
        "so", "also", "now", "well", "yeah", "yes", "yep", "no", "okay", "ok", "oh", "anyway", "and", "but", "plus", "hey", "hi", "um", "uh",
    ]

    /// Whether `at` begins the text, a line, a sentence or a list item.
    static func startsSentence(_ text: [Character], at: Int) -> Bool {
        var before = at - 1
        while before >= 0, text[before] == " " { before -= 1 }
        guard before >= 0, !text[before].isNewline else { return true }
        guard TypingEngine.sentenceEnders.contains(text[before]), before < at - 1 else { return false }
        var number = before - 1
        while number >= 0, text[number].isNumber { number -= 1 }
        return number == before - 1 || number < 0 || text[number].isNewline
    }
}

/// How much of what you said Hex edits out.
public enum DictationEditing: String, CaseIterable, Hashable, Sendable {
    /// Every word, um and uh included, as the model labs and Bassim's own transcriber keep them.
    case asSaid
    /// Without um and uh.
    case light
    /// Without um and uh, words said twice in a row, or what you take back with "scratch that".
    case clean

    public static let standard = DictationEditing.asSaid

    func edited(_ heard: [Character]) -> [Character] {
        switch self {
        case .asSaid: heard
        case .light: Self.withoutFillers(heard)
        case .clean: Self.withoutFillers(Self.withoutScratched(Self.withoutRepeats(heard)))
        }
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

    /// The second of a short word said twice, "the the" or "I I": only words nobody says twice on purpose, so "that
    /// that", "had had" and "very very" stay, and so does one a comma parts, as in "when you press it, it opens".
    static func withoutRepeats(_ text: [Character]) -> [Character] {
        var text = text
        for (first, second) in zip(Words.ranges(in: text), Words.ranges(in: text).dropFirst()).reversed() {
            let word = String(text[first]).lowercased()
            guard repeatable.contains(word), word == String(text[second]).lowercased() else { continue }
            guard text[first.upperBound ..< second.lowerBound].allSatisfy({ $0 == " " }) else { continue }
            text.removeSubrange(first.upperBound ..< second.upperBound)
        }
        return text
    }

    private static let repeatable: Set<String> = [
        "a", "an", "the", "i", "i'm", "to", "and", "of", "in", "on", "at", "for", "with", "it", "it's", "we", "you", "they",
        "he", "she", "my", "our", "this", "but", "or", "if", "is", "was", "are", "be",
    ]

    /// Each "scratch that" and what it takes back: the sentence it ends, or the one before when it starts one.
    static func withoutScratched(_ text: [Character]) -> [Character] {
        var text = text
        while let at = scratch(in: text) {
            var end = at.upperBound
            while end < text.count, ",.!?;:…".contains(text[end]) { end += 1 }
            while end < text.count, text[end] == " " { end += 1 }
            var start = sentenceStart(in: text, before: at.lowerBound)
            if !text[start ..< at.lowerBound].contains(where: \.isLetter) {
                while start > 0, text[start - 1] == " " { start -= 1 }
                if start > 0, TypingEngine.sentenceEnders.contains(text[start - 1]) { start -= 1 }
                start = sentenceStart(in: text, before: start)
            }
            if end < text.count, text[start].isUppercase, text[end].isLowercase { text[end] = Character(text[end].uppercased()) }
            text.removeSubrange(start ..< end)
        }
        return text
    }

    private static func scratch(in text: [Character]) -> Range<Int>? {
        let words = Words.ranges(in: text)
        for (first, second) in zip(words, words.dropFirst())
        where String(text[first]).lowercased() == "scratch" && String(text[second]).lowercased() == "that"
            && text[first.upperBound ..< second.lowerBound].allSatisfy({ $0 == " " }) {
            return first.lowerBound ..< second.upperBound
        }
        return nil
    }

    /// Where the sentence holding the character before `at` starts: past the last sentence end or line break.
    private static func sentenceStart(in text: [Character], before at: Int) -> Int {
        var start = at
        while start > 0 {
            let previous = text[start - 1]
            if previous.isNewline || TypingEngine.sentenceEnders.contains(previous) && start < text.count && text[start] == " " { break }
            start -= 1
        }
        while start < at, text[start] == " " { start += 1 }
        return start
    }
}

/// What you said, as Hex types it: edited, in its style, and with any list you spoke written as one. Its capitals are
/// the keyboard's (`DictationStyle.capitals`).
public struct DictationWriting: Hashable, Sendable {
    public var style = DictationStyle.standard
    public var editing = DictationEditing.standard
    /// "one, eggs, two, milk" written as a numbered list (`SpokenList`).
    public var lists = true

    public init(style: DictationStyle = .standard, editing: DictationEditing = .standard, lists: Bool = true) {
        self.style = style
        self.editing = editing
        self.lists = lists
    }

    public func written(_ heard: String) -> String {
        var text = editing.edited(Array(heard))
        text = Self.withoutDoubledPeriods(style.punctuated(text))
        if lists { text = SpokenList.written(text) }
        return String(style.openersLoosened(text))
    }

    /// ".." for ".", which Parakeet sometimes writes, keeping "...".
    private static func withoutDoubledPeriods(_ text: [Character]) -> [Character] {
        var text = text
        var at = 1
        while at < text.count {
            let run = text[at - 1] == "." && text[at] == "." && (at + 1 == text.count || text[at + 1] != ".") && (at < 2 || text[at - 2] != ".")
            if run { text.remove(at: at) } else { at += 1 }
        }
        return text
    }
}

extension KeyboardSettings {
    public var dictation: DictationWriting {
        DictationWriting(style: dictationStyle, editing: dictationEditing, lists: dictationLists)
    }
}
