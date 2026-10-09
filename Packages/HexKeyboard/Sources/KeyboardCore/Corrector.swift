public final class Corrector {
    public let source: any CandidateSource
    public var replacements: [String: String] = [:]
    public var names: [String: String] = [:]
    public var memory = TypingMemory() {
        didSet { cachedModel = nil }
    }
    public var grid = KeyGrid.standard

    private let lexicon: Lexicon?
    private var cachedModel: LanguageModel?

    /// With a `Lexicon` as its source, the corrector decodes your taps against your own touch model and words;
    /// any other source (like `UITextChecker`) only corrects spelling.
    public init(source: any CandidateSource) {
        self.source = source
        self.lexicon = source as? Lexicon
    }

    public func setReplacements(_ pairs: [(shortcut: String, phrase: String)]) {
        replacements = Dictionary(pairs.map { ($0.shortcut.lowercased(), $0.phrase) }) { first, _ in first }
    }

    public func setNames(_ words: [String]) {
        names = Dictionary(words.map { ($0.lowercased(), $0) }) { first, _ in first }
    }

    public func learn(_ samples: [TapSample]) {
        memory.touches.learn(samples, on: grid)
    }

    public func correction(for word: TypedWord, guessing: Bool = true) -> String? {
        let text = Substring(word.text)
        let lower = word.text.lowercased()
        if let phrase = replacements[lower] { return phrase == word.text ? nil : phrase }
        if memory.isKept(lower) { return nil }
        if let name = names[lower] {
            return word.text == name || word.text == word.text.uppercased() ? nil : name
        }
        guard guessing else { return nil }
        if let lexicon {
            guard let best = ranked(word).first(where: { !$0.isCompletion }), best.word != word.text else { return nil }
            if best.isLiteral { return lexicon.canonical(lower) == best.word && best.word != lower ? best.word : nil }
            return Words.matchCase(best.word, to: text)
        }
        guard !source.isWord(word.text), let guess = source.guesses(for: word).first else { return nil }
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
        if lexicon != nil {
            add(ranked(word).filter { !$0.isLiteral }.map(\.word), as: .candidate)
        } else {
            add(memory.completions(for: word.text), as: .candidate)
            add(source.completions(for: word.text), as: .candidate)
            if guessing, alternatives.count < 2 { add(source.guesses(for: word), as: .candidate) }
        }
        return [Suggestion(word.text, .literal)] + alternatives
    }

    func predictions(after previous: String?, context: String) -> [Suggestion] {
        var seen: Set<String> = []
        var words = (previous.map(memory.predictions(after:)) ?? []) + source.predictions(after: context)
        if let lexicon {
            let model = languageModel(lexicon)
            words = (words + lexicon.mostFrequent(count: 6)).sorted { model.logProbability($0, after: previous) > model.logProbability($1, after: previous) }
        }
        return words
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(3)
            .map { Suggestion($0, .candidate) }
    }
}

extension Corrector {
    struct Candidate {
        var word: String
        var logPosterior: Double
        var isCompletion: Bool
        var isLiteral: Bool
    }

    func ranked(_ typed: TypedWord) -> [Candidate] {
        guard let lexicon, !typed.text.isEmpty else { return [] }
        let model = languageModel(lexicon)
        let taps = evidence(for: typed)
        let literal = typed.text.lowercased()
        var candidates: [String: Candidate] = [:]
        func consider(_ word: String, logLikelihood: Double, isCompletion: Bool) {
            let lower = word.lowercased()
            let isLiteral = lower == literal
            let score = logLikelihood + model.logProbability(word, after: typed.previous)
            guard score > -.infinity, score > candidates[lower]?.logPosterior ?? -.infinity else { return }
            candidates[lower] = Candidate(word: word, logPosterior: score, isCompletion: isCompletion && !isLiteral, isLiteral: isLiteral)
        }
        for result in Decoder(lexicon: lexicon).decode(taps) {
            consider(result.word, logLikelihood: result.logLikelihood, isCompletion: result.isCompletion)
        }
        let literalWord = lexicon.canonical(literal) ?? typed.text
        consider(literalWord, logLikelihood: Decoder.logLikelihood(of: literalWord, given: taps), isCompletion: false)
        for word in memory.familiar where word.utf8.count + 1 >= taps.count && lexicon.logProbability(of: word) == nil {
            let exact = Decoder.logLikelihood(of: word, given: taps)
            let completed = Decoder.logLikelihood(of: word, given: taps, completing: true)
            consider(word, logLikelihood: max(exact, completed), isCompletion: completed > exact)
        }
        return candidates.values.sorted { $0.logPosterior > $1.logPosterior }
    }

    func evidence(for typed: TypedWord) -> [TapEvidence] {
        let letters = typed.text.lowercased().utf8.map(Lexicon.fold)
        let taps = typed.taps.count == letters.count ? typed.taps.map(Optional.some) : letters.map { _ in nil }
        let bounds = grid.bounds
        let stray = -Math.log(bounds.width * bounds.height)
        let frames = (0..<Lexicon.alphabet).map { grid.frame(of: String(UnicodeScalar(Lexicon.letter(at: $0)))).map(grid.cell(of:)) }
        let touches = (0..<Lexicon.alphabet).map { memory.touches.touches(for: String(UnicodeScalar(Lexicon.letter(at: $0))), signature: grid.signature) }
        return zip(letters, taps).map { letter, tap in
            guard let index = Lexicon.index(of: letter), let typedCell = frames[index] else { return .exact(letter) }
            let point = tap.map { ($0.x, $0.y) } ?? (typedCell.midX, typedCell.midY)
            let likelihoods = frames.indices.map { key in
                frames[key].map { memory.touches.logLikelihood(x: point.0, y: point.1, cell: $0, touches: touches[key]) } ?? -.infinity
            }
            return TapEvidence(letters: likelihoods, stray: stray)
        }
    }

    func languageModel(_ lexicon: Lexicon) -> LanguageModel {
        if let cachedModel { return cachedModel }
        let model = LanguageModel(lexicon: lexicon, memory: memory)
        cachedModel = model
        return model
    }
}

extension Corrector {
    /// The key a tap most likely meant: the touch model's likelihood for each key the tap reaches, times how likely
    /// that key is to come next after `prefix` (pass `nil` where words aren't expected). Keys without a label (shift,
    /// delete, return…) keep exactly the taps that land on them, and the space bar only trades taps with letters
    /// mid-word.
    public func key(atX x: Double, y: Double, in grid: KeyGrid, after prefix: String?) -> (row: Int, key: Int)? {
        guard let nearest = grid.index(atX: x, y: y), let nearestLabel = grid.rows[nearest.row][nearest.key].key.label else {
            return grid.index(atX: x, y: y)
        }
        let midWord = prefix.map { !$0.isEmpty } ?? false
        if nearestLabel == " ", !midWord { return nearest }
        let next = prefix.flatMap { prefix in lexicon.map { languageModel($0).next(after: prefix.lowercased()) } }
        var best = nearest, bestScore = -Double.infinity
        for (r, row) in grid.rows.enumerated() {
            for (k, item) in row.enumerated() {
                guard let label = item.key.label, label != " " || midWord, grid.reaches(label, x: x, y: y),
                      let likelihood = memory.touches.logLikelihood(x: x, y: y, for: label, on: grid) else { continue }
                let score = likelihood + (next?[label.lowercased()].map(Math.log) ?? 0)
                if score > bestScore { (best, bestScore) = ((r, k), score) }
            }
        }
        return best
    }
}
