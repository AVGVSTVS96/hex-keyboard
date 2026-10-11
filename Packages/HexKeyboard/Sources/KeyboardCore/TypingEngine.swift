public struct TypingEngine {
    public private(set) var layer: KeyboardLayer = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var traits: InputTraits
    public internal(set) var suggestions: [Suggestion] = []
    /// Leaves `suggestions` stale after each change, for a `SuggestionJob` to rank off the keystroke's path.
    public var defersSuggestions = false
    public internal(set) var suggestionsAreStale = false
    var revision = 0
    public var settings = KeyboardSettings()
    public var corrector: Corrector?

    private var spaceJustTyped = false
    private var shiftHold: ShiftHold?
    var taps: [Tap] = []
    var erased: [Int: Tap] = [:]
    var retyped: [TapSample] = []
    var pending: PendingWord?
    var stray: StraySpace?
    var revert: Revert?

    private enum ShiftHold { case pressed, typedWhileHeld }

    public init(traits: InputTraits = InputTraits()) {
        self.traits = traits
        self.layer = Self.initialLayer(for: traits.kind)
    }

    public mutating func update(_ traits: InputTraits) {
        if traits.kind != self.traits.kind { layer = Self.initialLayer(for: traits.kind) }
        self.traits = traits
    }

    public mutating func perform(_ action: KeyAction, in document: some TextDocument, tap: Tap? = nil) {
        switch action {
        case .shift:
            shift = shift == .off ? .on : .off
            return
        case .capsLock:
            shift = shift == .locked ? .off : .locked
            return
        case .layer(let target):
            layer = target
            suggestionsChanged(in: document)
            return
        case .nextKeyboard, .dismiss:
            return
        case .character, .space, .return, .tab, .delete:
            break
        }

        let wasSpace = spaceJustTyped
        let revert = self.revert
        spaceJustTyped = false
        self.revert = nil
        if wasSpace, action != .delete { corrector?.memory.recordAfterSpace(isSpace: action == .space) }

        switch action {
        case .character(let text):
            var typed = shift.isUppercase && layer == .letters ? text.uppercased() : text
            if settings.smartPunctuation, traits.smartPunctuation {
                if typed == "-", document.textBeforeInput?.last == "-" {
                    document.deleteBackward(1)
                    typed = "—"
                } else {
                    typed = Self.smartQuote(typed, after: document.textBeforeInput)
                }
            }
            if Self.wordEnders.contains(typed) {
                commitWord(in: document)
            } else if let tap, typed.allSatisfy(Words.isWordCharacter) {
                recordTap(tap, for: typed.lowercased(), in: document)
            }
            document.insert(typed)
            self.revert?.trailing = typed
            if layer != .letters, Self.returnsToLetters.contains(text) { layer = .letters }
            if shiftHold != nil { shiftHold = .typedWhileHeld }
        case .space:
            if wasSpace, let tap, joinBack(space: tap, in: document) {
                spaceJustTyped = true
            } else if wasSpace, settings.periodShortcut, traits.smartPunctuation, Self.endsSentenceable(document.textBeforeInput) {
                document.deleteBackward(1)
                document.insert(". ")
                stray = tap.map { StraySpace(tap: $0, swallowed: ". ", restored: " ", counted: true) }
            } else {
                let blank = document.textBeforeInput?.last.map(\.isWhitespace) ?? true
                commitWord(in: document, ending: tap)
                document.insert(" ")
                self.revert?.trailing = " "
                spaceJustTyped = true
                if blank, let tap { stray = StraySpace(tap: tap, swallowed: " ", restored: "", counted: wasSpace) }
            }
            if layer != .letters { layer = .letters }
        case .return:
            commitWord(in: document)
            document.insert("\n")
            self.revert?.trailing = "\n"
        case .tab:
            document.insert("\t")
        case .delete:
            stray = nil
            let offersRevert = revert?.isCommitted(before: document.textBeforeInput) == true
            document.deleteBackward(1)
            if offersRevert {
                self.revert = revert
                self.revert?.offered = true
            } else {
                eraseTap(in: document)
            }
        default:
            break
        }
        refreshShift(in: document)
        suggestionsChanged(in: document)
    }

    public mutating func deleteWord(in document: some TextDocument) {
        spaceJustTyped = false
        revert = nil
        if taps.isEmpty { pending = nil }
        taps = []
        erased = [:]
        retyped = []
        document.deleteBackward(Self.wordLength(before: document.textBeforeInput))
        refreshShift(in: document)
        suggestionsChanged(in: document)
    }

    public mutating func pressShift(doubleTap: Bool) {
        shift = doubleTap && settings.capsLock ? .locked : shift == .off ? .on : .off
        shiftHold = .pressed
    }

    public mutating func releaseShift(in document: some TextDocument) {
        let typed = shiftHold == .typedWhileHeld
        shiftHold = nil
        guard typed, shift == .on else { return }
        refreshShift(in: document)
    }

    public mutating func documentChanged(_ document: some TextDocument) {
        spaceJustTyped = false
        if Words.current(in: document.textBeforeInput ?? "").count != taps.count {
            taps = []
            erased = [:]
            retyped = []
        }
        refreshShift(in: document)
        suggestionsChanged(in: document)
    }

    public mutating func refreshShift(in document: some TextDocument) {
        guard shift != .locked, shiftHold == nil else { return }
        let mode = settings.autoCapitalization ? traits.autocapitalization : .none
        let capitalize = layer == .letters && Self.shouldCapitalize(document.textBeforeInput, mode: mode)
        shift = capitalize ? .on : .off
    }
}

extension TypingEngine {
    static let returnsToLetters: Set<String> = ["'"]
    static let wordEnders: Set<String> = [".", ",", "!", "?", ";", ":"]
    static let sentenceEnders: Set<Character> = [".", "!", "?"]
    static let closers: Set<Character> = [")", "]", "\"", "'", "”", "’"]

    static func initialLayer(for kind: InputKind) -> KeyboardLayer {
        switch kind {
        case .number, .decimal: .numbers
        default: .letters
        }
    }

    static func shouldCapitalize(_ text: String?, mode: Autocapitalization) -> Bool {
        let text = text ?? ""
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return text.last.map { $0.isWhitespace } ?? true
        case .sentences:
            guard let last = text.last(where: { $0 != " " && $0 != "\t" }) else { return true }
            return last.isNewline || (text.last == " " && sentenceEnders.contains(last))
        }
    }

    static func smartQuote(_ text: String, after before: String?) -> String {
        let opens = before?.last.map { $0.isWhitespace || Words.openers.contains($0) } ?? true
        switch text {
        case "'": return opens ? "‘" : "’"
        case "\"": return opens ? "“" : "”"
        default: return text
        }
    }

    static func endsSentenceable(_ text: String?) -> Bool {
        guard let text, text.last == " " else { return false }
        let beforeSpace = text.dropLast()
        guard let previous = beforeSpace.last else { return false }
        return previous.isLetter || previous.isNumber || closers.contains(previous)
    }

    static func wordLength(before text: String?) -> Int {
        guard let text, !text.isEmpty else { return 1 }
        let reversed = text.reversed()
        let whitespace = reversed.prefix { $0.isWhitespace }.count
        let rest = reversed.dropFirst(whitespace)
        guard let first = rest.first else { return max(whitespace, 1) }
        let isWord = first.isLetter || first.isNumber
        let word = isWord ? rest.prefix { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" }.count : 1
        return whitespace + word
    }
}
