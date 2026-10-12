/// P(word | previous word), from the lexicon and what you've typed.
///
/// Every level backs off to the next with Witten-Bell weights, which come from the counts themselves (a context
/// seen N times with T different words trusts itself N / (N + T)), so there is nothing to tune:
/// your next-word counts → your word counts → the lexicon → a word the lexicon doesn't know, spelled letter by
/// letter. How often you keep such new words is itself learned: (new + 1) / (all + 2), Laplace's rule of succession.
struct LanguageModel {
    let lexicon: Lexicon
    let memory: TypingMemory
    let novelty: Double

    static let spellingLogProbability = -Math.log(Double(Lexicon.alphabet))

    init(lexicon: Lexicon, memory: TypingMemory) {
        self.lexicon = lexicon
        self.memory = memory
        let novel = memory.counts.reduce(0) { $0 + (lexicon.logProbability(of: $1.key) == nil ? $1.value : 0) }
        novelty = (Double(novel) + 1) / (Double(memory.total) + 2)
    }

    func logProbability(_ word: String, after previous: String?) -> Double {
        var p = lexical(word)
        if memory.total > 0 {
            let types = Double(memory.counts.count)
            p = (Double(memory.count(of: word)) + types * p) / (Double(memory.total) + types)
        }
        if let previous {
            let (count, total, types) = memory.count(of: word, after: previous)
            if total > 0 { p = (Double(count) + Double(types) * p) / Double(total + types) }
        }
        return Math.log(p)
    }

    func lexical(_ word: String) -> Double {
        let known = lexicon.logProbability(of: word).map(Math.exp) ?? 0
        return (1 - novelty) * known + novelty * Math.exp(Self.spellingLogProbability * Double(word.utf8.count + 1))
    }

    /// P(next letter | the letters so far), over the lexicon and novel spellings, and P(the word ends here) as `" "`.
    /// Before a word starts, `" "` is how often you type a second space, by the rule of succession.
    func next(after prefix: String) -> [String: Double] {
        let length = Double(prefix.utf8.count)
        let node = lexicon.node(for: prefix)
        let novel = { (letters: Double) in novelty * Math.exp(Self.spellingLogProbability * letters) }
        let mass = { (node: Lexicon.Node?) in node.map { (1 - novelty) * Math.exp(lexicon.logMass($0)) } ?? 0 }
        let total = mass(node) + novel(length)
        var result: [String: Double] = [:]
        for (index, label) in Lexicon.labels.enumerated() {
            let child = node.flatMap { lexicon.child($0, Lexicon.letter(at: index)) }
            result[label] = (mass(child) + novel(length + 1)) / total
        }
        if prefix.isEmpty {
            let space = (Double(memory.spacesAfterSpace) + 1) / (Double(memory.keysAfterSpace) + 2)
            for (key, p) in result { result[key] = p * (1 - space) }
            result[" "] = space
        } else {
            let ends = node.flatMap(lexicon.logWord).map { (1 - novelty) * Math.exp($0) } ?? 0
            result[" "] = (ends + novel(length + 1)) / total
        }
        return result
    }
}
