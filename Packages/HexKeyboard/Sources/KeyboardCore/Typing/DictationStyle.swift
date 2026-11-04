/// How a dictation reads, in Wispr Flow's four styles: its capitals and all of its punctuation, never its words, which
/// are `DictationEditing`'s. Every style gives a question the model ended with a period its question mark. Formal
/// keeps every comma, ends every sentence, adds the comma after an opening "However" or "Actually" and lets one ! or ?
/// do. Casual keeps the capitals with less punctuation: no last period, no comma after an opening "So", "Hey" or
/// "Thanks", and a comma for a semicolon. Very casual is Casual in lowercase without the comma before "and", "but" or
/// "so". Excited is Formal with an exclamation mark ending the last sentence, every short one and every cheer.
public enum DictationStyle: String, CaseIterable, Hashable, Sendable {
    case formal
    case casual
    case veryCasual
    case excited

    public static let standard = DictationStyle.casual

    /// `text`'s sentence marks in this style, before a list it may end on is written as one.
    func punctuated(_ text: [Character]) -> [Character] {
        var text = Self.questionsMarked(text)
        switch self {
        case .formal:
            text = Self.marksSingled(text)
            if let last = text.last, last.isLetter || last.isNumber { text.append(".") }
        case .casual, .veryCasual:
            if text.last == ".", text.dropLast().last != "." { text.removeLast() }
        case .excited:
            text = Self.exclaimed(Self.marksSingled(text))
        }
        return text
    }

    /// `text`'s commas in this style, once its lists are written.
    func commas(_ text: [Character]) -> [Character] {
        switch self {
        case .formal, .excited: Self.transitionsSetOff(text)
        case .casual: Self.openersLoosened(Self.semicolonsLoosened(text))
        case .veryCasual: Self.conjunctionsLoosened(Self.openersLoosened(Self.semicolonsLoosened(text)))
        }
    }

    /// A sentence: from its first character to its mark (`mark`), or to the end of its line or the text.
    struct Sentence {
        var range: Range<Int>
        var mark: Int?
    }

    /// Each sentence in `text`, split after a period, question or exclamation mark that a space, a line break or the
    /// end follows, or at a line break. "..." is one mark, and a period inside a number splits nothing.
    static func sentences(in text: [Character]) -> [Sentence] {
        var sentences: [Sentence] = []
        var start: Int?
        var at = 0
        while at < text.count {
            let character = text[at]
            if character.isNewline {
                if let begun = start { sentences.append(Sentence(range: begun ..< trimmedEnd(text, begun, at), mark: nil)) }
                start = nil
            } else if start == nil, character != " " {
                start = at
            }
            if let begun = start, TypingEngine.sentenceEnders.contains(character) {
                var end = at
                while end + 1 < text.count, TypingEngine.sentenceEnders.contains(text[end + 1]) { end += 1 }
                if end + 1 == text.count || text[end + 1].isWhitespace {
                    sentences.append(Sentence(range: begun ..< end + 1, mark: end))
                    start = nil
                }
                at = end
            }
            at += 1
        }
        if let begun = start { sentences.append(Sentence(range: begun ..< trimmedEnd(text, begun, text.count), mark: nil)) }
        return sentences.filter { !$0.range.isEmpty }
    }

    private static func trimmedEnd(_ text: [Character], _ start: Int, _ end: Int) -> Int {
        var end = end
        while end > start, text[end - 1] == " " { end -= 1 }
        return end
    }

    /// Whether the sentence's mark is a lone period, not part of "...".
    private static func endsWithPeriod(_ text: [Character], _ sentence: Sentence) -> Bool {
        guard let mark = sentence.mark, text[mark] == "." else { return false }
        return mark == 0 || text[mark - 1] != "."
    }

    /// The words of the sentence, lowercased with straight apostrophes.
    private static func words(_ text: [Character], _ sentence: Sentence) -> [String] {
        let sentence = Array(text[sentence.range])
        return Words.ranges(in: sentence).map { Words.plain(String(sentence[$0]).lowercased()) }
    }

    /// A question the model wrote with a period, or with nothing at the end: one that opens with a verb before its
    /// subject ("Are you", "Can we", "Did it"), a question word before a verb ("What do", "Where's"), or ends on a tag
    /// after a comma (", right", ", isn't it").
    static func questionsMarked(_ text: [Character]) -> [Character] {
        var text = text
        for sentence in sentences(in: text).reversed() where asks(words(text, sentence), tagged: tagged(text, sentence)) {
            if endsWithPeriod(text, sentence), let mark = sentence.mark {
                text[mark] = "?"
            } else if sentence.mark == nil, let last = text[sentence.range].last, last.isLetter || last.isNumber {
                text.insert("?", at: sentence.range.upperBound)
            }
        }
        return text
    }

    private static func asks(_ words: [String], tagged: Bool) -> Bool {
        if tagged { return true }
        let words = Array(words.drop { leadIns.contains($0) })
        guard let first = words.first else { return false }
        if questionWords.contains(first) { return words.count > 1 }
        guard words.count > 1 else { return false }
        let second = words[1]
        if ["what", "where", "when", "why", "who", "how", "which"].contains(first) { return verbs.contains(second) }
        guard verbs.contains(first), subjects.contains(second) else { return false }
        return !(["do", "have", "had"].contains(first) && ["it", "that", "this"].contains(second))
    }

    /// Whether the sentence ends on ", right", ", okay" or a verb and its subject, as in ", isn't it".
    private static func tagged(_ text: [Character], _ sentence: Sentence) -> Bool {
        var end = sentence.mark.map { endsWithPeriod(text, sentence) ? $0 : -1 } ?? sentence.range.upperBound
        guard end > sentence.range.lowerBound else { return false }
        while end > sentence.range.lowerBound, text[end - 1] == " " { end -= 1 }
        let tail = Array(text[sentence.range.lowerBound ..< end])
        let words = Words.ranges(in: tail)
        guard words.count >= 3 else { return false }
        func word(_ index: Int) -> String { Words.plain(String(tail[words[index]]).lowercased()) }
        func comma(before index: Int) -> Bool { words[index].lowerBound >= 2 && tail[words[index].lowerBound - 2] == "," }
        let last = words.count - 1
        if ["right", "okay", "ok", "yeah"].contains(word(last)), comma(before: last) { return true }
        return word(last - 1).hasSuffix("n't") && subjects.contains(word(last)) && comma(before: last - 1)
    }

    private static let leadIns: Set<String> = ["so", "and", "but", "okay", "ok", "hey", "well", "um", "uh", "oh", "also", "then", "now", "yeah", "anyway", "wait", "sorry"]
    private static let questionWords: Set<String> = ["what's", "where's", "when's", "why's", "who's", "how's", "what're", "where're", "who're", "how're"]
    private static let verbs: Set<String> = [
        "are", "is", "am", "was", "were", "do", "does", "did", "can", "could", "would", "will", "should", "shall", "may",
        "might", "have", "has", "had", "isn't", "aren't", "wasn't", "weren't", "doesn't", "didn't", "can't", "couldn't",
        "wouldn't", "won't", "shouldn't", "haven't", "hasn't",
    ]
    private static let subjects: Set<String> = [
        "you", "we", "i", "they", "he", "she", "it", "there", "that", "this", "y'all", "anyone", "anybody", "everyone", "someone",
    ]

    /// One ! or ? where the model wrote several, as in "!!" or "??".
    static func marksSingled(_ text: [Character]) -> [Character] {
        var text = text
        var at = 1
        while at < text.count {
            if "!?".contains(text[at]), text[at] == text[at - 1] { text.remove(at: at) } else { at += 1 }
        }
        return text
    }

    /// Excited's marks: the last sentence, every sentence of up to three words and every one that opens with a cheer
    /// ends with ! where it would end with a period, never a question or "...".
    static func exclaimed(_ text: [Character]) -> [Character] {
        var text = text
        let sentences = sentences(in: text)
        for (index, sentence) in sentences.enumerated().reversed() {
            let words = words(text, sentence)
            let excites = index == sentences.count - 1 || words.count <= 3 || words.first.map(cheers.contains) == true
            guard excites, !words.isEmpty else { continue }
            if endsWithPeriod(text, sentence), let mark = sentence.mark {
                text[mark] = "!"
            } else if sentence.mark == nil, let last = text[sentence.range].last, last.isLetter || last.isNumber {
                text.insert("!", at: sentence.range.upperBound)
            }
        }
        return text
    }

    private static let cheers: Set<String> = [
        "wow", "yay", "congrats", "congratulations", "awesome", "amazing", "great", "nice", "cool", "thanks", "thank", "hey",
        "hi", "hello", "love", "woohoo", "omg", "yes", "finally", "perfect", "sweet", "haha", "happy", "welcome", "cheers",
        "hooray", "can't", "good", "fantastic", "incredible", "excellent", "brilliant", "best",
    ]

    /// Formal's comma after a sentence's opening transition: "However, ", "Actually, ", "Hopefully, ".
    static func transitionsSetOff(_ text: [Character]) -> [Character] {
        var text = text
        let words = Words.ranges(in: text)
        for (index, word) in words.enumerated().reversed() where index + 1 < words.count {
            guard transitions.contains(String(text[word]).lowercased()), startsSentence(text, at: word.lowerBound),
                  words[index + 1].lowerBound == word.upperBound + 1, text[word.upperBound] == " ",
                  String(text[words[index + 1]]).lowercased() != "not" else { continue }
            text.insert(",", at: word.upperBound)
        }
        return text
    }

    private static let transitions: Set<String> = [
        "however", "also", "anyway", "anyways", "actually", "basically", "honestly", "meanwhile", "otherwise", "additionally",
        "unfortunately", "fortunately", "luckily", "sadly", "personally", "apparently", "hopefully", "frankly", "regardless",
        "nevertheless", "nonetheless", "therefore", "furthermore", "moreover", "alternatively", "ultimately", "overall",
        "lastly", "anyhow", "seriously", "technically", "surprisingly", "interestingly",
    ]

    /// Without the comma after a sentence's opening word, as in "So, " or "Hey, ", in the casual styles.
    static func openersLoosened(_ text: [Character]) -> [Character] {
        var text = text
        for word in Words.ranges(in: text).reversed() where word.upperBound < text.count && text[word.upperBound] == "," {
            guard openers.contains(Words.plain(String(text[word]).lowercased())), startsSentence(text, at: word.lowerBound) else { continue }
            text.remove(at: word.upperBound)
        }
        return text
    }

    private static let openers: Set<String> = [
        "so", "also", "now", "well", "yeah", "yes", "yep", "no", "nope", "okay", "ok", "oh", "anyway", "anyways", "and",
        "but", "plus", "hey", "hi", "hello", "um", "uh", "actually", "honestly", "basically", "thanks", "sure", "alright",
        "right", "cool", "great", "nice", "wow", "sorry", "however", "then", "like", "look", "listen", "btw", "lol",
    ]

    /// "; " as ", ", which casual writing uses in its place.
    static func semicolonsLoosened(_ text: [Character]) -> [Character] {
        var text = text
        for at in text.indices where text[at] == ";" && at + 1 < text.count && text[at + 1] == " " && at > 0 && Words.isWordCharacter(text[at - 1]) {
            text[at] = ","
        }
        return text
    }

    /// Very casual's: no comma between two clauses joined by "and", "but", "so", "or", "then" or "because".
    static func conjunctionsLoosened(_ text: [Character]) -> [Character] {
        var text = text
        for word in Words.ranges(in: text).reversed() where word.lowerBound >= 3 {
            guard text[word.lowerBound - 1] == " ", text[word.lowerBound - 2] == ",", Words.isWordCharacter(text[word.lowerBound - 3]),
                  conjunctions.contains(String(text[word]).lowercased()), word.upperBound < text.count, text[word.upperBound] == " " else { continue }
            text.remove(at: word.lowerBound - 2)
        }
        return text
    }

    private static let conjunctions: Set<String> = ["and", "but", "so", "or", "then", "because", "cause", "cuz"]

    /// Whether `at` begins the text, a line, a sentence or a list item.
    static func startsSentence(_ text: [Character], at: Int) -> Bool {
        var before = at - 1
        while before >= 0, text[before] == " " { before -= 1 }
        guard before >= 0, !text[before].isNewline else { return true }
        if text[before] == "•", before == 0 || text[before - 1].isNewline { return true }
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
    /// Without um and uh, words said twice in a row, "like" and "you know" said between commas, what you take back with
    /// "scratch that", and what you correct as you go ("at two, I mean three").
    case clean

    public static let standard = DictationEditing.asSaid

    func edited(_ heard: [Character]) -> [Character] {
        switch self {
        case .asSaid: heard
        case .light: Self.withoutFillers(heard)
        case .clean: Self.withoutFillers(Self.withoutAsides(Self.withoutScratched(Self.withoutCorrections(Self.withoutRepeats(heard)))))
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
    /// "like", "you know" and "I mean" said between commas, or opening a sentence before one, as in "it was, like,
    /// huge" or "You know, it works". A capital passes to the next word.
    static func withoutAsides(_ text: [Character]) -> [Character] {
        var text = text
        var searched = 0
        while let aside = aside(in: text, from: searched) {
            var start = aside.lowerBound
            var end = aside.upperBound
            let opens = DictationStyle.startsSentence(text, at: start)
            if opens, end < text.count, text[end] == "," {
                end += 1
                while end < text.count, text[end] == " " { end += 1 }
                if text[start].isUppercase, end < text.count, text[end].isLowercase { text[end] = Character(text[end].uppercased()) }
            } else if start >= 2, text[start - 2] == ",", text[start - 1] == " ", end < text.count, text[end] == "," || TypingEngine.sentenceEnders.contains(text[end]) {
                start -= 2
                if text[end] == "," { end += 1 }
            } else {
                searched = aside.upperBound
                continue
            }
            text.removeSubrange(start ..< end)
            searched = start
        }
        return text
    }

    private static let asides: [[String]] = [["like"], ["you", "know"], ["i", "mean"]]

    private static func aside(in text: [Character], from: Int) -> Range<Int>? {
        let words = Words.ranges(in: text)
        for (index, word) in words.enumerated() where word.lowerBound >= from {
            for aside in asides where phrase(text, words, at: index, is: aside) {
                return word.lowerBound ..< words[index + aside.count - 1].upperBound
            }
        }
        return nil
    }

    /// Whether the words from `index` are `phrase`, with only spaces between them.
    private static func phrase(_ text: [Character], _ words: [Range<Int>], at index: Int, is phrase: [String]) -> Bool {
        guard index + phrase.count <= words.count else { return false }
        for (offset, said) in phrase.enumerated() {
            let word = words[index + offset]
            guard Words.plain(String(text[word]).lowercased()) == said else { return false }
            if offset > 0, !text[words[index + offset - 1].upperBound ..< word.lowerBound].allSatisfy({ $0 == " " }) { return false }
        }
        return true
    }

    /// What you correct as you say it: "at two, I mean three" is "at three", and "on Tuesday, actually Wednesday" is
    /// "on Wednesday". The correction is one to three words after "I mean", "actually", "no wait", "or rather", "make
    /// that", or "sorry", "no" or "wait" with a comma, up to the next mark; it takes the place of as many words before
    /// the comma, or of the nearest number or name when it's one, and only words that carry no subject or verb, so "I'm
    /// busy, sorry I can't" and "it's fine, I mean it works" stay.
    static func withoutCorrections(_ text: [Character]) -> [Character] {
        var text = text
        var searched = 0
        while let fix = correction(in: text, from: searched) {
            text.replaceSubrange(fix.range, with: fix.with)
            searched = fix.range.lowerBound + fix.with.count
        }
        return text
    }

    private static let cues: [(words: [String], comma: Bool)] = [
        (["i", "mean"], false), (["i", "meant"], false), (["no", "wait"], false), (["wait", "no"], false),
        (["or", "rather"], false), (["make", "that"], false), (["actually"], false), (["sorry"], true), (["no"], true), (["wait"], true),
    ]

    private static func correction(in text: [Character], from: Int) -> (range: Range<Int>, with: [Character])? {
        let words = Words.ranges(in: text)
        for (index, word) in words.enumerated() where word.lowerBound >= max(from, 2) && index > 0 {
            guard text[word.lowerBound - 1] == " ", text[word.lowerBound - 2] == ",", words[index - 1].upperBound == word.lowerBound - 2 else { continue }
            for cue in cues where phrase(text, words, at: index, is: cue.words) {
                let comma = word.lowerBound - 2
                var after = words[index + cue.words.count - 1].upperBound
                if after < text.count, text[after] == "," { after += 1 } else if cue.comma { continue }
                guard after < text.count, text[after] == " " else { continue }
                let said = clause(text, words, from: index + cue.words.count, startingAt: after + 1)
                guard (1 ... 3).contains(said.count) else { continue }
                let before = clause(text, words, endingAt: index - 1)
                guard let replaced = replaced(text, words, before, by: said) else { continue }
                var with = Array(text[words[said.first!].lowerBound ..< words[said.last!].upperBound])
                with += text[words[replaced.last!].upperBound ..< comma]
                if text[words[replaced[0]].lowerBound].isUppercase, with[0].isLowercase { with[0] = Character(with[0].uppercased()) }
                var end = words[said.last!].upperBound
                if end < text.count, text[end] == ",", replaced.last == before.last { end += 1 }
                return (words[replaced[0]].lowerBound ..< end, with)
            }
        }
        return nil
    }

    /// The indices of the words from `index` on that only spaces part, starting at `startingAt`, if the clause ends at
    /// a mark or the end.
    private static func clause(_ text: [Character], _ words: [Range<Int>], from index: Int, startingAt: Int) -> [Int] {
        guard index < words.count, words[index].lowerBound == startingAt else { return [] }
        var clause = [index]
        while let last = clause.last, last + 1 < words.count, text[words[last].upperBound ..< words[last + 1].lowerBound].allSatisfy({ $0 == " " }) {
            clause.append(last + 1)
            if clause.count > 3 { return [] }
        }
        let end = words[clause.last!].upperBound
        return end == text.count || ",.!?;:".contains(text[end]) ? clause : []
    }

    /// The indices of the words that only spaces part, ending with `index`, back to the clause's start.
    private static func clause(_ text: [Character], _ words: [Range<Int>], endingAt index: Int) -> [Int] {
        var clause = [index]
        while let first = clause.first, first > 0, text[words[first - 1].upperBound ..< words[first].lowerBound].allSatisfy({ $0 == " " }) {
            clause.insert(first - 1, at: 0)
        }
        return clause
    }

    /// The words of `before` that `said` takes the place of.
    private static func replaced(_ text: [Character], _ words: [Range<Int>], _ before: [Int], by said: [Int]) -> [Int]? {
        guard before.count >= said.count else { return nil }
        let spelled = { (index: Int) in Words.plain(String(text[words[index]]).lowercased()) }
        guard !said.contains(where: { unreplaceable.contains(spelled($0)) }) else { return nil }
        let first = said[0]
        let kind: ((Int) -> Bool)? = isNumber(spelled(first)) ? { isNumber(spelled($0)) }
            : text[words[first].lowerBound].isUppercase ? { text[words[$0].lowerBound].isUppercase } : nil
        var start = before.count - said.count
        if let kind, !kind(before[start]) {
            guard let match = before[...start].lastIndex(where: kind) else { return nil }
            start = match
        }
        let span = Array(before[start ..< start + said.count])
        return span.contains(where: { unreplaceable.contains(spelled($0)) }) ? nil : span
    }

    private static func isNumber(_ word: String) -> Bool {
        word.allSatisfy(\.isNumber) || numberWords.contains(word)
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "fifteen",
        "twenty", "thirty", "forty", "fifty", "hundred", "thousand", "noon", "midnight",
    ]

    /// Words a correction never replaces or is: subjects, verbs and joiners, which say it's a clause of its own.
    private static let unreplaceable: Set<String> = [
        "i", "i'm", "i'll", "i've", "i'd", "me", "you", "you're", "we", "we're", "they", "they're", "he", "she", "it", "it's",
        "that's", "there's", "is", "was", "are", "were", "am", "be", "been", "do", "does", "did", "don't", "can", "can't",
        "will", "won't", "would", "should", "could", "have", "has", "had", "not", "and", "or", "but", "so", "if", "think",
        "know", "guess", "mean", "just",
    ]
}


/// What you said, as Hex types it: edited, in its style, and with any list you spoke written as one. Its capitals are
/// the keyboard's, set where it goes in (`capitals`).
public struct DictationWriting: Hashable, Sendable {
    public var style = DictationStyle.standard
    public var editing = DictationEditing.standard
    /// "one, eggs, two, milk" written as a numbered list (`SpokenList`).
    public var lists = true
    /// Auto-Capitalization, which a dictation follows as typing does.
    public var capitalizes = true

    public init(style: DictationStyle = .standard, editing: DictationEditing = .standard, lists: Bool = true, capitalizes: Bool = true) {
        self.style = style
        self.editing = editing
        self.lists = lists
        self.capitalizes = capitalizes
    }

    /// The capitals a dictation gets in a field that asks for `field`'s: none with Auto-Capitalization off or in
    /// very casual (`TypingEngine.fitted`).
    public func capitals(in field: Autocapitalization) -> Autocapitalization {
        capitalizes && style != .veryCasual ? field : .none
    }

    public func written(_ heard: String) -> String {
        var text = style.punctuated(Self.withoutDoubledPeriods(editing.edited(Array(heard))))
        if lists { text = SpokenList.written(text) }
        return String(style.commas(text))
    }

    /// `heard` as Hex types it at the start of a field that capitalizes sentences, as a message's does.
    public func typed(_ heard: String, lexicon: Lexicon?) -> String {
        TypingEngine.fitted(written(heard), between: "", and: nil, lexicon: lexicon, capitals: capitals(in: .sentences))
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
        DictationWriting(style: dictationStyle, editing: dictationEditing, lists: dictationLists, capitalizes: autoCapitalization)
    }
}
