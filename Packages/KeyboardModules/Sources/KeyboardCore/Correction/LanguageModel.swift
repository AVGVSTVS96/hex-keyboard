/// P(word | previous word), from the lexicon and what you've typed.
///
/// Every level backs off to the next with Witten-Bell weights, which come from the counts themselves (a context
/// seen N times with T different words trusts itself N / (N + T)): your next-word counts → your word counts → the
/// lexicon → a word the lexicon doesn't know, spelled letter by letter. Each word's count in a context gives `discount`
/// to the level below (absolute discounting), since a word seen there once is mostly chance and shouldn't outrank a
/// word the level below knows far better. How often you keep new words is itself learned: (new + 1) / (all + 2),
/// Laplace's rule of succession.
struct LanguageModel {
    let lexicon: Lexicon
    let memory: TypingMemory
    let novelty: Double
    let app: AppWords?

    static let discount = 0.5
    static let spellingLogProbability = -Math.log(Double(Lexicon.alphabet))

    /// `novel` is `novel(in:lexicon:)`, when the caller keeps it counted.
    init(lexicon: Lexicon, memory: TypingMemory, novel: Int? = nil, app: AppWords? = nil) {
        self.app = app
        self.lexicon = lexicon
        self.memory = memory
        let novel = novel ?? Self.novel(in: memory, lexicon: lexicon)
        novelty = (Double(novel) + 1) / (Double(memory.total) + 2)
    }

    /// How many of the words you've typed the lexicon doesn't know.
    static func novel(in memory: TypingMemory, lexicon: Lexicon) -> Int {
        memory.counts.reduce(0) { $0 + (lexicon.logProbability(of: $1.key) == nil ? $1.value : 0) }
    }

    func logProbability(_ word: String, after previous: String?) -> Double {
        Math.log(probability(word, after: previous, earlier: nil, over: unigram(word)))
    }

    /// The same for the word you'll type next, after both words before it, with what the network `expected` from the
    /// text before under your next-word counts. Corrections leave the network out: its vocabulary is the corpus's
    /// commonest words, so it would push the rest down. Over the network your counts trust themselves N / (N + 8T):
    /// it reads the last 16 words where they read one or two, and on Bassim's own messages that weight ranks best.
    /// `previous` is "" at a sentence's start and nil when unknown; `earlier` is the word before it, read the same way.
    func predictor(after previous: String?, earlier: String?, expected: Network.Next?) -> (String) -> Double {
        { word in
            let below = unigram(word)
            guard let expected else { return Math.log(probability(word, after: previous, earlier: earlier, over: below)) }
            return Math.log(probability(word, after: previous, earlier: earlier, over: expected.probability(of: word, below: below), trusting: 8))
        }
    }

    private func probability(_ word: String, after previous: String?, earlier: String?, over corpus: Double, trusting trust: Double = 1) -> Double {
        var p = corpus
        for context in TypingMemory.contexts(previous, earlier) {
            let (count, total, types) = memory.count(of: word, after: context)
            let below = trust * Double(types)
            if total > 0 { p = (max(Double(count) - Self.discount, 0) + (below + Self.discount * Double(types)) * p) / (Double(total) + below) }
        }
        return app?.probability(of: word, after: previous, below: p) ?? p
    }

    private func unigram(_ word: String) -> Double {
        let p = lexical(word)
        guard memory.total > 0 else { return p }
        let types = Double(memory.counts.count)
        return (Double(memory.count(of: word)) + types * p) / (Double(memory.total) + types)
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
