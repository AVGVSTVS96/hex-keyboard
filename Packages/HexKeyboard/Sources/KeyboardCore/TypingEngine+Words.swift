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

extension TypingEngine {
    var correcting: Bool { settings.autoCorrection && traits.allowsCorrection }

    public var showsSuggestions: Bool {
        switch traits.kind {
        case .email, .url, .number, .decimal: false
        default: settings.predictiveText
        }
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
        case .literal:
            corrector?.memory.keep(suggestion.text)
        case .correction, .candidate:
            document.deleteBackward(word.count)
            document.insert(suggestion.text)
        }
        if !suggestion.text.contains(" ") { corrector?.memory.record(suggestion.text, after: previous) }
        revert = nil
        taps = []
        document.insert(" ")
        refreshShift(in: document)
        refreshSuggestions(in: document)
    }

    mutating func commitWord(in document: some TextDocument) {
        defer { taps = [] }
        guard let corrector else { return }
        let text = document.textBeforeInput ?? ""
        let word = Words.current(in: text)
        guard !word.isEmpty else { return }
        var final = String(word)
        let midWord = document.textAfterInput?.first.map(Words.isWordCharacter) ?? false
        if correcting, !midWord, Words.isCorrectable(word, in: text),
           let correction = corrector.correction(for: TypedWord(final, taps: taps), guessing: traits.spellChecking) {
            document.deleteBackward(word.count)
            document.insert(correction)
            revert = Revert(original: final, replacement: correction)
            final = correction
        }
        if !final.contains(" ") { corrector.memory.record(final, after: Words.previous(before: word, in: text)) }
        if final.count == taps.count {
            onTapSamples(zip(taps, final).map { TapSample(tap: $0, intended: String($1).lowercased()) })
        }
    }

    mutating func refreshSuggestions(in document: some TextDocument) {
        guard let corrector, showsSuggestions else { return suggestions = [] }
        let text = document.textBeforeInput ?? ""
        let word = Words.current(in: text)
        let typed = TypedWord(String(word), taps: taps)
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
