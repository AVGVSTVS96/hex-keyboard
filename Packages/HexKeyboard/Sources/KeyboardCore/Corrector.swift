public final class Corrector {
    public let source: any CandidateSource
    public var replacements: [String: String] = [:]
    public var names: [String: String] = [:]
    public var memory = TypingMemory()

    public init(source: any CandidateSource) {
        self.source = source
    }

    public func setReplacements(_ pairs: [(shortcut: String, phrase: String)]) {
        replacements = Dictionary(pairs.map { ($0.shortcut.lowercased(), $0.phrase) }) { first, _ in first }
    }

    public func setNames(_ words: [String]) {
        names = Dictionary(words.map { ($0.lowercased(), $0) }) { first, _ in first }
    }

    public func correction(for word: TypedWord, guessing: Bool = true) -> String? {
        let text = Substring(word.text)
        let lower = word.text.lowercased()
        if let phrase = replacements[lower] { return phrase == word.text ? nil : phrase }
        if memory.isKept(lower) { return nil }
        if let name = names[lower] {
            return word.text == name || word.text == word.text.uppercased() ? nil : name
        }
        guard guessing, !source.isWord(word.text), let guess = source.guesses(for: word).first else { return nil }
        return Words.matchCase(guess, to: text)
    }

    func suggestions(for word: TypedWord, correcting: Bool, guessing: Bool) -> [Suggestion] {
        let typed = Substring(word.text)
        var seen: Set<String> = [word.text.lowercased()]
        var alternatives: [Suggestion] = []
        func add(_ candidates: some Sequence<String>, as kind: Suggestion.Kind) {
            for candidate in candidates where alternatives.count < 2 {
                let text = kind == .correction ? candidate : Words.matchCase(candidate, to: typed)
                if seen.insert(text.lowercased()).inserted { alternatives.append(Suggestion(text, kind)) }
            }
        }
        if correcting, let correction = correction(for: word, guessing: guessing) { add([correction], as: .correction) }
        let lower = word.text.lowercased()
        add(names.filter { $0.key.count > lower.count && $0.key.hasPrefix(lower) }.values.sorted(), as: .candidate)
        add(memory.completions(for: word.text), as: .candidate)
        add(source.completions(for: word.text), as: .candidate)
        if guessing, alternatives.count < 2 { add(source.guesses(for: word), as: .candidate) }
        return [Suggestion(word.text, .literal)] + alternatives
    }

    func predictions(after previous: String?, context: String) -> [Suggestion] {
        let learned = previous.map(memory.predictions(after:)) ?? []
        var seen: Set<String> = []
        return (learned + source.predictions(after: context))
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(3)
            .map { Suggestion($0, .candidate) }
    }
}
