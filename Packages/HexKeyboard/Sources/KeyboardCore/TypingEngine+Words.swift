struct Revert: Hashable {
    var original: String
    var replacement: String
    var trailing: String?
    var offered = false

    func isCommitted(before text: String?) -> Bool {
        guard let trailing, !offered else { return false }
        return text?.hasSuffix(replacement + trailing) == true
    }

    func isOffered(before text: String) -> Bool {
        offered && text.hasSuffix(replacement)
    }
}

/// A committed word whose taps become labels once you move on without changing it.
struct PendingWord: Hashable {
    var word: String
    var typed: String
    var taps: [Tap]
    var retyped: [TapSample]
    var ending: Tap?

    var samples: [TapSample] {
        let letters = word.lowercased().map(String.init)
        let spelled = letters.count == taps.count ? zip(taps, letters).map { TapSample(tap: $0, intended: $1) } : []
        return spelled + retyped + (ending.map { [TapSample(tap: $0, intended: " ")] } ?? [])
    }
}

extension TypingEngine {
    var correcting: Bool { settings.autoCorrection && traits.allowsCorrection }

    public var showsSuggestions: Bool {
        switch traits.kind {
        case .email, .url, .number, .decimal: false
        default: settings.predictiveText
        }
    }

    /// The key a touch at (x, y) means, using your touch model and, in words, what's likely to come next.
    public func key(atX x: Double, y: Double, in grid: KeyGrid, document: some TextDocument) -> (row: Int, key: Int)? {
        guard let corrector else { return grid.index(atX: x, y: y) }
        let text = document.textBeforeInput ?? ""
        let word = Words.current(in: text)
        let inWords = layer == .letters && correcting && (word.isEmpty || Words.isCorrectable(word, in: text))
        return corrector.key(atX: x, y: y, in: grid, after: inWords ? String(word) : nil)
    }

    /// Learns from the last word you kept. Call when typing pauses for good, like when the keyboard goes away.
    public mutating func endSession() {
        learnPending()
        taps = []
        erased = [:]
        retyped = []
    }

    public mutating func accept(_ suggestion: Suggestion, in document: some TextDocument) {
        let text = document.textBeforeInput ?? ""
        let word = Words.current(in: text)
        let previous = Words.previous(before: word, in: text)
        switch suggestion.kind {
        case .revert:
            guard let revert, revert.isOffered(before: text) else { return }
            document.deleteBackward(revert.replacement.count)
            document.insert(revert.original)
            corrector?.memory.keep(revert.original)
            pending?.word = revert.original
        case .literal:
            corrector?.memory.keep(suggestion.text)
            hold(suggestion.text, typed: String(word))
        case .correction, .candidate:
            document.deleteBackward(word.count)
            document.insert(suggestion.text)
            hold(suggestion.text, typed: String(word))
        }
        if !suggestion.text.contains(" ") { corrector?.memory.record(suggestion.text, after: previous) }
        revert = nil
        taps = []
        document.insert(" ")
        refreshShift(in: document)
        refreshSuggestions(in: document)
    }

    mutating func commitWord(in document: some TextDocument, ending: Tap? = nil) {
        let shortcut = self.shortcut
        defer {
            taps = []
            erased = [:]
            retyped = []
            self.shortcut = nil
        }
        guard let corrector else { return }
        let text = document.textBeforeInput ?? ""
        let word = Words.current(in: text)
        guard !word.isEmpty else { return }
        var final = String(word), typedText = final
        var previous = Words.previous(before: word, in: text)
        let midWord = document.textAfterInput?.first.map(Words.isWordCharacter) ?? false
        guard correcting, !midWord, Words.isCorrectable(word, in: text) else { return settle(final, typed: final, after: previous, ending: ending) }
        let typed = TypedWord(final, taps: taps, previous: previous)
        if let shortcut, text.dropLast(word.count).hasSuffix(". "),
           case let before = Words.current(in: String(text.dropLast(word.count + 2))).lowercased(),
           let joined = corrector.joined(nil, space: shortcut, TypedWord(final.lowercased(), taps: taps, previous: before)) {
            document.deleteBackward(word.count + 2)
            document.insert(" " + joined)
            revert = Revert(original: ". " + final, replacement: " " + joined)
            corrector.memory.unrecordSpaceAfterSpace()
            taps = [shortcut] + taps
            final = joined
            typedText = joined
            previous = before
        } else if let pending, let join = join(typed, after: pending, in: text) {
            document.deleteBackward(pending.word.count + 1 + word.count)
            document.insert(join.word)
            revert = Revert(original: "\(pending.word) \(final)", replacement: join.word)
            corrector.memory.forget(pending.word, after: join.previous)
            taps = pending.taps + [join.space] + taps
            self.pending = nil
            final = join.word
            typedText = join.word
            previous = join.previous
        } else if let correction = corrector.correction(for: typed, guessing: traits.spellChecking) {
            document.deleteBackward(word.count)
            document.insert(correction)
            revert = Revert(original: final, replacement: correction)
            final = correction
        }
        settle(final, typed: typedText, after: previous, ending: ending)
    }

    private mutating func settle(_ word: String, typed: String, after previous: String?, ending: Tap?) {
        if !word.contains(" ") { corrector?.memory.record(word, after: previous) }
        hold(word, typed: typed, ending: ending)
    }

    /// Whether the space between the last word and this one was really a letter you missed ("a out" → "about").
    private func join(_ typed: TypedWord, after pending: PendingWord, in text: String) -> (word: String, space: Tap, previous: String?)? {
        guard let corrector, let space = pending.ending, pending.taps.count == pending.typed.count else { return nil }
        let head = String(text.dropLast(typed.text.count))
        guard head.hasSuffix(pending.word + " ") else { return nil }
        let firstText = Words.current(in: String(head.dropLast()))
        guard firstText == pending.word[...] else { return nil }
        let before = Words.previous(before: firstText, in: String(head.dropLast()))
        let first = TypedWord(pending.typed, taps: pending.taps, previous: before)
        guard let joined = corrector.joined(first, space: space, TypedWord(typed.text, taps: typed.taps, previous: pending.word.lowercased())) else { return nil }
        return (Words.matchCase(joined, to: Substring(pending.typed)), space, before)
    }

    private mutating func hold(_ word: String, typed: String, ending: Tap? = nil) {
        learnPending()
        pending = PendingWord(word: word, typed: typed, taps: taps, retyped: retyped, ending: ending)
    }

    mutating func learnPending() {
        if let pending { corrector?.learn(pending.samples) }
        pending = nil
    }

    mutating func recordTap(_ tap: Tap, for letter: String, in document: some TextDocument) {
        if let pending, document.textBeforeInput?.hasSuffix(pending.word) == true { self.pending = nil }
        if let erased = erased.removeValue(forKey: taps.count), let grid = corrector?.grid,
           grid.reaches(letter, x: erased.x, y: erased.y) {
            retyped.append(TapSample(tap: erased, intended: letter))
        }
        taps.append(tap)
    }

    mutating func eraseTap(in document: some TextDocument) {
        if let tap = taps.popLast() {
            erased[taps.count] = tap
        } else if let pending, pending.taps.count == pending.word.count, Words.current(in: document.textBeforeInput ?? "") == pending.word[...] {
            taps = pending.taps
            retyped = pending.retyped
            if let ending = pending.ending { erased[taps.count] = ending }
            self.pending = nil
        }
    }

    mutating func refreshSuggestions(in document: some TextDocument) {
        guard let corrector, showsSuggestions else { return suggestions = [] }
        let text = document.textBeforeInput ?? ""
        let word = Words.current(in: text)
        let typed = TypedWord(String(word), taps: taps, previous: Words.previous(before: word, in: text))
        if let revert, revert.isOffered(before: text) {
            let completions = corrector.suggestions(for: typed, correcting: false, guessing: false).dropFirst()
            suggestions = [Suggestion(revert.original, .revert)] + completions
        } else if word.isEmpty {
            suggestions = corrector.predictions(after: Words.previous(before: word, in: text), context: text)
        } else {
            let correcting = correcting && Words.isCorrectable(word, in: text)
            suggestions = corrector.suggestions(for: typed, correcting: correcting, guessing: traits.spellChecking)
        }
    }
}
