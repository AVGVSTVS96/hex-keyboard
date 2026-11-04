public final class Corrector {
    public let source: any CandidateSource
    public let network: Network?
    public var replacements: [String: String] = [:]
    public var names: [String: String] = [:]
    /// What you've taught it, changed only through `record`, `forget` and `changeMemory`, which change it in place: a
    /// property observer here would copy all of it on every change.
    public private(set) var memory = TypingMemory()
    public var app: String? {
        didSet { if app != oldValue { forgetRankings() } }
    }
    public var grid = KeyGrid.standard {
        didSet { if !grid.isSame(as: oldValue) { forgetRankings() } }
    }

    let lexicon: Lexicon?
    /// How many of the words in `memory` the lexicon doesn't know, counted once and then kept up to date.
    private var novel: Int?
    private var rankings: [Ranking: [Candidate]] = [:]
    private var keyShares: [String: [Double]] = [:]
    private var generation = 0
    private var reading: (tokens: [Int], state: Network.State, next: Network.Next)?
    private var unknown: Double?

    private struct Ranking: Hashable {
        var typed: TypedWord
        var alone: Bool
        var inRun: Bool
    }

    /// With a `Lexicon` as its source, the corrector decodes your taps against your own touch model and words;
    /// any other source (like `UITextChecker`) only corrects spelling. The `Network` tells it what words come next.
    public init(source: any CandidateSource, network: Network? = nil) {
        self.source = source
        self.network = network
        self.lexicon = source as? Lexicon
    }

    /// A corrector with the same words, touches and grid, and caches of its own.
    func snapshot() -> Corrector {
        let copy = Corrector(source: source, network: network)
        copy.reading = reading
        copy.unknown = unknown
        copy.replacements = replacements
        copy.names = names
        copy.memory = memory
        copy.app = app
        copy.grid = grid
        copy.novel = novel
        copy.rankings = rankings
        copy.keyShares = keyShares
        copy.generation = generation
        return copy
    }

    /// Keeps what a snapshot ranked, if this corrector's words, touches and grid haven't changed since.
    func adopt(_ snapshot: Corrector) {
        reading = snapshot.reading ?? reading
        unknown = unknown ?? snapshot.unknown
        guard snapshot.generation == generation else { return }
        rankings.merge(snapshot.rankings) { mine, _ in mine }
        keyShares.merge(snapshot.keyShares) { mine, _ in mine }
        if novel == nil { novel = snapshot.novel }
    }

    /// Counts a word you kept, after the one before it.
    public func record(_ word: String, after previous: String?, earlier: String? = nil) {
        let total = memory.total
        memory.record(word, after: previous, earlier: earlier)
        if let app {
            if memory.apps == nil { memory.apps = [:] }
            memory.apps?[app, default: AppWords()].record(Words.plain(word), after: previous.map(Words.plain))
        }
        recount(word, by: 1, since: total)
    }

    /// Takes back one count of a word you didn't keep after all.
    public func forget(_ word: String, after previous: String?, earlier: String? = nil) {
        let total = memory.total
        memory.forget(word, after: previous, earlier: earlier)
        if let app { memory.apps?[app]?.forget(Words.plain(word), after: previous.map(Words.plain)) }
        recount(word, by: -1, since: total)
    }

    /// Any other change to what's learned, or a memory in its place.
    public func changeMemory(_ change: (inout TypingMemory) -> Void) {
        let counts = memory.counts
        change(&memory)
        if memory.counts != counts { novel = nil }
        forgetRankings()
    }

    private func recount(_ word: String, by step: Int, since total: Int) {
        if memory.total == total + step, let count = novel {
            novel = lexicon?.logProbability(of: Words.plain(word)) == nil ? count + step : count
        } else if memory.total != total {
            novel = nil
        }
        forgetRankings()
    }

    private func forgetRankings() {
        rankings = [:]
        keyShares = [:]
        generation += 1
    }

    public func setReplacements(_ pairs: [(shortcut: String, phrase: String)]) {
        replacements = Dictionary(pairs.map { ($0.shortcut.lowercased(), $0.phrase) }) { first, _ in first }
    }

    /// Contact names from `UILexicon` include everyday words ("A", "My", "The"). Typed lowercase, those mean the word,
    /// so a name the lexicon spells lowercase is left out.
    public func setNames(_ words: [String]) {
        let names = words.filter { lexicon?.canonical($0) != $0.lowercased() }
        self.names = Dictionary(names.map { ($0.lowercased(), $0) }) { first, _ in first }
    }

    public func learn(_ samples: [TapSample]) {
        memory.touches.learn(samples, on: grid)
        forgetRankings()
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
            let ranked = ranked(word)
            guard let best = ranked.first(where: { !$0.isCompletion }), best.word != word.text else { return nil }
            if best.isLiteral { return lexicon.canonical(lower) == best.word && best.word != lower ? best.word : nil }
            if isKnown(word), let literal = ranked.first(where: \.isLiteral), literal.logLikelihood >= best.logLikelihood { return nil }
            return Words.matchCase(best.word, to: text)
        }
        guard !source.isWord(word.text), let guess = source.guesses(for: word).first else { return nil }
        return Words.matchCase(guess, to: text)
    }

    /// `context` is the text before the word, when known.
    func suggestions(for word: TypedWord, context: String? = nil, correcting: Bool, applying: Bool = true, guessing: Bool) -> [Suggestion] {
        let typed = Substring(word.text)
        var seen: Set<String> = [word.text.lowercased()]
        var alternatives: [Suggestion] = []
        if word.text.contains(" ") {
            let words = correcting && guessing ? split(word, context: context) : nil
            return [Suggestion(word.text, .literal)] + (words.map { [Suggestion($0, .candidate)] } ?? [])
        }
        if correcting, let correction = correction(for: word, guessing: guessing), seen.insert(correction.lowercased()).inserted {
            alternatives.append(Suggestion(correction, applying ? .correction : .candidate))
        }
        func add(_ candidates: some Sequence<String>, as kind: Suggestion.Kind) {
            for candidate in candidates where alternatives.count < 2 {
                let text = Words.matchCase(candidate, to: typed)
                if seen.insert(text.lowercased()).inserted { alternatives.append(Suggestion(text, kind)) }
            }
        }
        if correcting, guessing, let split = split(word, context: context) { add([split], as: .candidate) }
        let lower = word.text.lowercased()
        add(names.filter { $0.key.count > lower.count && $0.key.hasPrefix(lower) }.values.sorted(), as: .candidate)
        if lexicon != nil {
            add(completions(for: word, context: context), as: .candidate)
        } else {
            add(memory.completions(for: word.text), as: .candidate)
            add(source.completions(for: word.text), as: .candidate)
            if guessing, alternatives.count < 2 { add(source.guesses(for: word), as: .candidate) }
        }
        return [Suggestion(word.text, .literal)] + alternatives
    }

    func predictions(after previous: String?, earlier: String?, context: String) -> [Suggestion] {
        var seen: Set<String> = []
        var words = TypingMemory.contexts(previous, earlier).reversed().flatMap(memory.predictions(after:)) + source.predictions(after: context)
        if let lexicon {
            let expected = expected(after: context)
            let predict = languageModel(lexicon).predictor(after: previous, earlier: earlier, expected: expected)
            let likeliest = (expected?.likeliest(12) ?? []).map { lexicon.canonical($0) ?? $0 }
            words = (words + likeliest + lexicon.mostFrequent(count: 6))
                .map { ($0, predict($0)) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        return words
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(3)
            .map { Suggestion($0, .candidate) }
    }

    /// What the word you're typing may become, likeliest first: the decoder's readings of your taps and the words likely
    /// to come next, each scored by your taps and by the next-word model. `context` is the text before the word.
    func completions(for typed: TypedWord, context: String?) -> [String] {
        guard let lexicon else { return [] }
        let earlier = context.flatMap { Words.context(before: $0[$0.endIndex...], in: $0).earlier }
        let expected = context.flatMap(expected(after:))
        let predict = languageModel(lexicon).predictor(after: typed.previous, earlier: earlier, expected: expected)
        let taps = evidence(for: typed, touches: memory.touches)
        let literal = typed.text.lowercased()
        var fits = Dictionary(ranked(typed).filter { !$0.isLiteral }.map { ($0.word, $0.logLikelihood) }) { first, _ in first }
        let following = TypingMemory.contexts(typed.previous, earlier).flatMap(memory.predictions(after:))
            + (expected?.likeliest(24, startingWith: typed.text) ?? []).map { lexicon.canonical($0) ?? $0 }
        for word in following where fits[word] == nil && word.lowercased() != literal {
            fits[word] = Decoder.logLikelihood(of: word, given: taps, touches: memory.touches, on: grid, completing: true)
        }
        return fits.filter { $0.value > -.infinity }
            .map { ($0.key, $0.value + predict($0.key)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .map(\.0)
    }

    /// What the network expects after `text`. It goes on from what it read for the text before when this text only adds
    /// to it, up to twice `Network.window` tokens, as long as the windows it learned from, and otherwise reads the last
    /// `Network.window` tokens afresh.
    func expected(after text: String) -> Network.Next? {
        guard let network, let lexicon else { return nil }
        let tokens = network.tokens(before: text)
        if let reading, reading.tokens == tokens { return reading.next }
        let state = if let reading, tokens.count <= 2 * Network.window, tokens.starts(with: reading.tokens) {
            network.read(tokens[reading.tokens.count...], from: reading.state)
        } else {
            network.read(tokens.suffix(Network.window), from: network.start)
        }
        let next = next(at: state, network, lexicon)
        reading = (tokens, state, next)
        return next
    }

    private func next(at state: Network.State, _ network: Network, _ lexicon: Lexicon) -> Network.Next {
        let unknown = unknown ?? 1 - (Network.specials.count..<network.words).reduce(0) {
            $0 + (lexicon.logProbability(of: network.spelling(of: $1)).map(Math.exp) ?? 0)
        }
        self.unknown = unknown
        return Network.Next(network: network, logProbabilities: network.logProbabilities(at: state), unknown: max(unknown, .ulpOfOne))
    }

    /// The words Check Spelling underlines: words with no digits that aren't in the lexicon (nor its possessive),
    /// a name, a text replacement or a word you've kept.
    public func misspellings(in text: String) -> [Range<String.Index>] {
        text.split { !Words.isWordCharacter($0) }
            .map { $0.drop(while: Words.apostrophes.contains).dropLast(while: Words.apostrophes.contains) }
            .filter { !$0.isEmpty && !$0.contains(where: \.isNumber) && !isSpelled(String($0.map { $0 == "’" ? "'" : $0 })) }
            .map { $0.startIndex..<$0.endIndex }
    }

    private func isSpelled(_ word: String) -> Bool {
        let lower = word.lowercased()
        if source.isWord(word) || memory.isKept(lower) || names[lower] != nil || replacements[lower] != nil { return true }
        return lower.hasSuffix("'s") && source.isWord(String(word.dropLast(2)))
    }
}

extension Corrector {
    struct Candidate {
        var word: String
        var logLikelihood: Double
        var logPosterior: Double
        var isCompletion: Bool
        var isLiteral: Bool
    }

    /// Candidates for what you meant, likeliest first. `alone` leaves out the words you've typed, so only the lexicon
    /// and your touches speak; `inRun` reads a word out of a longer run (`split`), which needs whole words, not
    /// completions.
    func ranked(_ typed: TypedWord, alone: Bool = false, inRun: Bool = false) -> [Candidate] {
        let key = Ranking(typed: typed, alone: alone, inRun: inRun)
        if let cached = rankings[key] { return cached }
        let candidates = rank(typed, alone: alone, inRun: inRun)
        rankings[key] = candidates
        return candidates
    }

    private func rank(_ typed: TypedWord, alone: Bool, inRun: Bool) -> [Candidate] {
        guard let lexicon, !typed.text.isEmpty else { return [] }
        let words = alone ? TypingMemory() : memory
        let model = alone ? LanguageModel(lexicon: lexicon, memory: words) : languageModel(lexicon)
        let taps = evidence(for: typed, touches: memory.touches)
        let literal = typed.text.lowercased()
        var candidates: [String: Candidate] = [:]
        func consider(_ word: String, logLikelihood: Double, isCompletion: Bool) {
            let lower = word.lowercased()
            let isLiteral = lower == literal
            let score = logLikelihood + model.logProbability(word, after: typed.previous)
            guard score > -.infinity, score > candidates[lower]?.logPosterior ?? -.infinity else { return }
            candidates[lower] = Candidate(word: word, logLikelihood: logLikelihood, logPosterior: score, isCompletion: isCompletion && !isLiteral, isLiteral: isLiteral)
        }
        func likelihood(_ word: String, completing: Bool = false) -> Double {
            Decoder.logLikelihood(of: word, given: taps, touches: memory.touches, on: grid, completing: completing)
        }
        for result in Decoder(lexicon: lexicon).decode(taps, budget: inRun ? Decoder.wordBudget : Decoder.budget) {
            consider(result.word, logLikelihood: likelihood(result.word, completing: result.isCompletion), isCompletion: result.isCompletion)
        }
        let literalWord = lexicon.canonical(literal) ?? typed.text
        consider(literalWord, logLikelihood: likelihood(literalWord), isCompletion: false)
        for word in words.familiar where word.utf8.count + 1 >= taps.count && lexicon.logProbability(of: word) == nil {
            if inRun {
                if word.utf8.count <= taps.count + 1 { consider(word, logLikelihood: likelihood(word), isCompletion: false) }
                continue
            }
            let exact = likelihood(word)
            let completed = likelihood(word, completing: true)
            consider(word, logLikelihood: max(exact, completed), isCompletion: completed > exact)
        }
        return candidates.values.sorted { $0.logPosterior > $1.logPosterior }
    }

    /// A word that stands on its own, which autocorrect replaces only when your touches fit the other word better: one
    /// you've kept, or a real word that, typed dead center on its keys, still reads as itself. Reading it with an
    /// apostrophe added ("its" → "it's") doesn't count against it.
    func isKnown(_ word: TypedWord) -> Bool {
        if memory.isKept(word.text) { return true }
        guard lexicon?.isWord(word.text) == true || memory.count(of: word.text) > 1 else { return false }
        let centers = word.text.lowercased().utf8.map { letter in
            let label = String(UnicodeScalar(Lexicon.fold(letter)))
            let frame = grid.frame(of: label)
            return Tap(x: frame?.midX ?? 0, y: frame?.midY ?? 0, key: label)
        }
        guard let perfect = ranked(TypedWord(word.text, taps: centers), alone: true).first(where: { !$0.isCompletion }), !perfect.isLiteral else { return true }
        return perfect.word.contains("'")
    }

    /// What each tap says about the letter it meant: where it landed, or for a word typed without its taps (one you went
    /// back to), only the key it hit (`shares`). A space tap may have meant a letter too.
    func evidence(for typed: TypedWord, touches: TouchModel) -> [TapEvidence] {
        let letters = typed.text.lowercased().utf8.map(Lexicon.fold)
        let tapped = typed.taps.count == letters.count
        let bounds = grid.bounds
        let stray = -Math.log(bounds.width * bounds.height)
        let keys = touches.layout(grid)
        return letters.indices.map { index in
            let letter = letters[index]
            guard let label = letter == 32 ? " " : Lexicon.index(of: letter).map({ Lexicon.labels[$0] }), grid.frame(of: label) != nil else {
                return .exact(letter)
            }
            guard tapped else { return TapEvidence(letters: Array(shares(of: label).prefix(Lexicon.alphabet)), stray: stray) }
            let tap = typed.taps[index]
            let likelihoods = Lexicon.labels.map { keys.logLikelihood(x: tap.x, y: tap.y, for: $0) ?? -.infinity }
            return TapEvidence(letters: likelihoods, stray: stray, point: Tap(x: tap.x, y: tap.y, key: label))
        }
    }

    /// How well a tap known only by the key it hit fits each key (a–z, the apostrophe, then the space bar): it may have
    /// landed anywhere on that key, so each key counts by its share of the taps landing there against the hit key's own,
    /// at the hit key's center.
    func shares(of hit: String) -> [Double] {
        if let cached = keyShares[hit] { return cached }
        guard let frame = grid.frame(of: hit) else { return [] }
        let keys = memory.touches.layout(grid), cell = grid.cell(of: frame), steps = 5
        let points = (0..<(steps * steps)).map { step in
            (cell.x + (Double(step / steps) + 0.5) * cell.width / Double(steps), cell.y + (Double(step % steps) + 0.5) * cell.height / Double(steps))
        }
        func mass(_ label: String) -> Double {
            points.reduce(-Double.infinity) { Math.logSumExp($0, keys.logLikelihood(x: $1.0, y: $1.1, for: label) ?? -.infinity) }
        }
        let center = keys.logLikelihood(x: frame.midX, y: frame.midY, for: hit) ?? 0, own = mass(hit)
        let result = (Lexicon.labels + [" "]).map { center + mass($0) - own }
        keyShares[hit] = result
        return result
    }

    func languageModel(_ lexicon: Lexicon) -> LanguageModel {
        let novel = novel ?? LanguageModel.novel(in: memory, lexicon: lexicon)
        self.novel = novel
        return LanguageModel(lexicon: lexicon, memory: memory, novel: novel, app: app.flatMap { memory.apps?[$0] })
    }
}

extension Corrector {
    /// The word a space tap spelled if it meant a letter: between two words ("a out" → "about"), or with one side
    /// missing when it was a stray space before a word ("ut" → "but") or after one ("jo" → "job").
    func joined(_ first: TypedWord?, space: Tap, _ second: TypedWord?) -> String? {
        let parts = [first, second].compactMap { $0 }
        guard let lexicon, !parts.isEmpty, parts.allSatisfy({ !$0.text.isEmpty && $0.taps.count == $0.text.count }),
              case let keys = memory.touches.layout(grid),
              let asSpace = keys.logLikelihood(x: space.x, y: space.y, for: " "),
              let letter = Lexicon.labels.dropLast().max(by: {
                  keys.logLikelihood(x: space.x, y: space.y, for: $0) ?? -.infinity < keys.logLikelihood(x: space.x, y: space.y, for: $1) ?? -.infinity
              }) else { return nil }
        let together = TypedWord((first?.text ?? "") + letter + (second?.text ?? ""), taps: (first?.taps ?? []) + [space] + (second?.taps ?? []),
                                 previous: first?.previous ?? second?.previous)
        guard let word = ranked(together).first(where: { !$0.isCompletion && (lexicon.isWord($0.word) || memory.count(of: $0.word) > 1) }) else { return nil }
        var apart = 0.0, apartLikelihood = asSpace
        for (index, part) in parts.enumerated() {
            let previous = index == 0 && first == nil ? "" : part.previous
            guard let best = ranked(TypedWord(part.text, taps: part.taps, previous: previous)).first(where: { !$0.isCompletion }) else { return nil }
            apart += best.logPosterior
            apartLikelihood += best.logLikelihood
        }
        apart += asSpace
        if parts.count == 1 {
            let secondSpace = languageModel(lexicon).next(after: "")[" "] ?? 0.5
            apart += Math.log(secondSpace)
            if word.logPosterior + Math.log(1 - secondSpace) <= apart { return nil }
        } else if word.logPosterior <= apart {
            return nil
        }
        if parts.allSatisfy(isKnown), word.logLikelihood <= apartLikelihood { return nil }
        return word.word
    }
}

extension Corrector {
    /// The words a run of taps spells when its spaces went astray ("freatvday" → "great day", "iloveyou" → "I love you",
    /// "ab out" → "about"), each word read from its own taps after the word before it, with any typo of its own. Between
    /// two words the space may have been typed, missed, or hit as a letter on the row above the space bar, where a thumb
    /// that misses it lands; a space tap inside a word may have meant a letter. Only the likeliest words up to each point
    /// go on, so each word is read once and stays cached as the taps after it come in. A single word is read as several
    /// only when that's likelier than every reading of its taps as one known word.
    func split(_ typed: TypedWord, context: String? = nil) -> String? {
        let letters = Array(typed.text), spaced = letters.contains(" ")
        guard let lexicon, letters.count >= 3, typed.taps.isEmpty || typed.taps.count == letters.count,
              let spaceRow = grid.index(of: " ")?.row, spaced || !isKnown(typed) else { return nil }
        let keys = memory.touches.layout(grid)
        func isWord(_ candidate: Candidate) -> Bool {
            lexicon.isWord(candidate.word) || memory.count(of: candidate.word) > 1 || memory.isKept(candidate.word)
        }
        func meant(_ range: Range<Int>, after previous: String?) -> Candidate? {
            guard letters[range.lowerBound] != " ", letters[range.upperBound - 1] != " " else { return nil }
            let word = TypedWord(String(letters[range]), taps: typed.taps.isEmpty ? [] : Array(typed.taps[range]), previous: previous)
            let ranked = ranked(word, inRun: true)
            guard let best = ranked.first(where: { !$0.isCompletion && isWord($0) }) else { return nil }
            let typedAlone = spaced && (range.lowerBound == 0 || letters[range.lowerBound - 1] == " ")
                && (range.upperBound == letters.count || letters[range.upperBound] == " ")
            guard typedAlone, !best.isLiteral, isKnown(word), let literal = ranked.first(where: \.isLiteral),
                  literal.logLikelihood >= best.logLikelihood else { return best }
            return literal
        }
        /// A space, or a letter on the row above the space bar, may have been the space between two words.
        func asSpace(_ index: Int) -> Double? {
            let label = String(letters[index]).lowercased()
            guard label == " " || grid.index(of: label)?.row == spaceRow - 1 else { return nil }
            guard !typed.taps.isEmpty else { return shares(of: label).last }
            return keys.logLikelihood(x: typed.taps[index].x, y: typed.taps[index].y, for: " ")
        }
        var runs: [Int: [Run]] = [0: [Run(words: [], likelihood: 0, score: 0)]]
        var finished: [Run] = []
        for start in letters.indices {
            for run in runs[start] ?? [] {
                for end in (start + 1)...min(letters.count, start + Self.longestWord) {
                    guard let word = meant(start..<end, after: run.words.last?.lowercased() ?? typed.previous) else { continue }
                    func extended(by logLikelihood: Double) -> Run {
                        Run(words: run.words + [word.word], likelihood: run.likelihood + word.logLikelihood + logLikelihood,
                            score: run.score + word.logPosterior + logLikelihood)
                    }
                    if end == letters.count {
                        if spaced || !run.words.isEmpty { Run.keep(extended(by: 0), in: &finished) }
                    } else {
                        Run.keep(extended(by: Decoder.editLogProbability), in: &runs[end, default: []])
                        if end + 1 < letters.count, let space = asSpace(end) { Run.keep(extended(by: space), in: &runs[end + 1, default: []]) }
                    }
                }
            }
        }
        let whole = spaced ? -Double.infinity : ranked(typed).first(where: isWord)?.logPosterior ?? -.infinity
        let likely = finished.filter { $0.score > whole }
        guard let best = likely.count == 1 ? likely.first : likely.map({ ($0, inContext($0, typed, context)) }).max(by: { $0.1 < $1.1 })?.0
        else { return nil }
        let words = best.words.joined(separator: " ")
        return words.lowercased() == typed.text.lowercased() ? nil : Words.matchCase(words, to: Substring(typed.text))
    }

    /// A reading of a run so far: its words, how well they fit their taps, and that with each word's likelihood after the one before.
    struct Run {
        var words: [String]
        var likelihood: Double
        var score: Double

        static let kept = 3

        static func keep(_ run: Run, in runs: inout [Run]) {
            runs.insert(run, at: runs.firstIndex { $0.score < run.score } ?? runs.count)
            if runs.count > kept { runs.removeLast() }
        }
    }

    /// How well a reading fits its taps and the words before it, each word scored after the words before it, with the
    /// network's say when there is `context`, the text before the run.
    func inContext(_ run: Run, _ typed: TypedWord, _ context: String?) -> Double {
        guard let lexicon else { return run.score }
        let model = languageModel(lexicon)
        var previous = typed.previous, earlier = context.flatMap { Words.context(before: $0[$0.endIndex...], in: $0).earlier }
        var state = context.flatMap { expected(after: $0) == nil ? nil : reading?.state }
        var total = run.likelihood
        for word in run.words {
            let next = state.flatMap { state in network.map { next(at: state, $0, lexicon) } }
            total += model.predictor(after: previous, earlier: earlier, expected: next)(word)
            (earlier, previous) = (previous, word.lowercased())
            state = state.flatMap { state in network.map { $0.read([$0.id(of: Words.plain(word).lowercased()) ?? Network.unknown], from: state) } }
        }
        return total
    }

    static let longestWord = 20
}
