public struct TypingEngine {
    public private(set) var layer: KeyboardLayer = .letters
    public private(set) var shift: ShiftState = .off
    public var emojiHistory = EmojiHistory()
    /// Finds emoji for the word in the suggestion bar.
    public var emojiCatalog: EmojiCatalog?
    /// The panel open over the bar, and what its search holds.
    public private(set) var panel: Panel?
    public private(set) var query = ""
    public private(set) var traits: InputTraits
    public internal(set) var suggestions: [Suggestion] = []
    /// Emoji for the word being typed, or the one just typed, which take the bar's last slot.
    public internal(set) var emojiSuggestions: [String] = []
    /// Leaves `suggestions` stale after each change, for a `SuggestionJob` to rank off the keystroke's path.
    public var defersSuggestions = false
    public internal(set) var suggestionsAreStale = false
    /// Which key a touch means, made for the text as it is after every change.
    public internal(set) var keyMap: KeyMap?
    /// The text before the word the suggestions were ranked for: a tap on one replaces only that word.
    var suggestionsBefore = ""
    var revision = 0
    public var settings = KeyboardSettings() {
        didSet {
            guard settings != oldValue else { return }
            if settings.autoCapitalization != oldValue.autoCapitalization, text.isKnown { refreshShift() }
            suggestionsChanged()
        }
    }
    public var corrector: Corrector?
    /// How the host likely wraps its text, for moving the caret up and down lines.
    public var lineLayout: (any LineLayout)?
    private var lineGoal: LineGoal?
    /// The one copy of the text the engine reads. The keyboard's edits reach it through `write` and `moveCursor`, the
    /// host's reports through `documentChanged`.
    public private(set) var text = TextState()

    /// The space just before the caret, if the keyboard just put it there: one you typed, or one a pick from the bar
    /// added after its word, which punctuation typed next goes before, as on Apple's keyboard.
    var lastSpace: LastSpace?
    private var shiftHold: ShiftHold?
    /// Delete went down with text in the panel's search, so holding it empties the search and stops there.
    private var deleteHeldInSearch = false
    private var sessionEnded = false
    var typing = WordTaps()
    var pending: PendingWord?
    var stray: StraySpace?
    var revert: Revert?

    private enum ShiftHold { case pressed, typedWhileHeld }
    enum LastSpace { case typed, picked }

    public init(traits: InputTraits = InputTraits()) {
        self.traits = traits
        self.layer = Self.initialLayer(for: traits.kind)
    }

    public mutating func update(_ traits: InputTraits) {
        guard traits != self.traits else { return }
        if traits.kind != self.traits.kind { layer = Self.initialLayer(for: traits.kind) }
        self.traits = traits
        if text.isKnown { refreshShift() }
        suggestionsChanged()
    }

    public mutating func perform(_ action: KeyAction, in document: some TextDocument, tap: Tap? = nil) {
        attach(document)
        switch action {
        case .shift:
            shift = shift == .off ? .on : .off
            return
        case .capsLock:
            shift = shift == .locked ? .off : .locked
            return
        case .layer(let target):
            layer = target
            suggestionsChanged()
            return
        case .nextKeyboard, .dismiss, .emoji:
            return
        case .character, .space, .return, .tab, .delete:
            break
        }
        if panel != nil, action != .delete || !query.isEmpty { return search(action) }
        if panel != nil, deleteHeldInSearch { return }

        let wasSpace = lastSpace == .typed, picked = lastSpace == .picked
        let revert = self.revert
        lastSpace = nil
        self.revert = nil
        if wasSpace, action != .delete { corrector?.changeMemory { $0.recordAfterSpace(isSpace: action == .space) } }

        switch action {
        case .character(let key):
            var typed = shift.isUppercase && layer == .letters ? key.uppercased() : key
            if settings.smartPunctuation, traits.smartPunctuation {
                if typed == "-", text.before.last == "-", text.owned >= 1 {
                    write("", replacing: 1, in: document)
                    typed = "—"
                } else {
                    typed = Self.smartQuote(typed, after: text.before)
                }
            }
            if Self.wordEnders.contains(typed) {
                commitWord(in: document)
                if picked, text.before.last == " ", text.owned >= 1 {
                    write("", replacing: 1, in: document)
                    typed += " "
                }
            } else if let tap, typed.allSatisfy(Words.isWordCharacter) {
                recordTap(tap, for: typed.lowercased())
            }
            write(typed, in: document)
            self.revert?.trailing = typed
            if layer != .letters, Self.returnsToLetters.contains(key) { layer = .letters }
            if shiftHold != nil { shiftHold = .typedWhileHeld }
        case .space:
            if wasSpace, let tap, joinBack(space: tap, in: document) {
                lastSpace = .typed
            } else if wasSpace, settings.periodShortcut, traits.smartPunctuation, text.owned >= 1, Self.endsSentenceable(text.before) {
                write(". ", replacing: 1, in: document)
                stray = tap.map { StraySpace(tap: $0, swallowed: ". ", restored: " ", counted: true) }
            } else {
                let blank = text.before.last.map(\.isWhitespace) ?? true
                commitWord(in: document, ending: tap)
                write(" ", in: document)
                self.revert?.trailing = " "
                lastSpace = .typed
                if blank, let tap { stray = StraySpace(tap: tap, swallowed: " ", restored: "", counted: wasSpace) }
            }
            if layer != .letters { layer = .letters }
        case .return:
            commitWord(in: document)
            write("\n", in: document)
            self.revert?.trailing = "\n"
        case .tab:
            write("\t", in: document)
        case .delete:
            stray = nil
            let offersRevert = revert?.isCommitted(before: text.before) == true
            write("", replacing: 1, in: document)
            if offersRevert {
                self.revert = revert
                self.revert?.offered = true
            } else {
                eraseTap()
            }
        default:
            break
        }
        refreshShift()
        suggestionsChanged()
    }

    /// Returns false for events the engine ignores, like a letter's touch down: those change nothing to redraw.
    @discardableResult
    public mutating func handle(_ event: KeyboardEvent, in document: some TextDocument) -> Bool {
        switch event {
        case .down(let key, let tapCount):
            switch key.action {
            case .shift: pressShift(doubleTap: tapCount == 2)
            case .delete:
                deleteHeldInSearch = panel != nil && !query.isEmpty
                perform(key.action, in: document)
            case .capsLock, .layer: perform(key.action, in: document)
            default: return false
            }
        case .up(let key):
            if key.action == .delete { deleteHeldInSearch = false }
            guard key.action == .shift else { return false }
            releaseShift(in: document)
        case .type(let key, let tap):
            perform(key.action == .space ? .space : .character(tap.key), in: document, tap: tap)
        case .slide(let text):
            let layer = self.layer
            perform(.character(text), in: document)
            if self.layer == layer { perform(.layer(.letters), in: document) }
        case .trigger(let key) where key.action == .emoji:
            show(panel == .emoji ? nil : .emoji)
        case .trigger(let key):
            guard key.action == .return || key.action == .tab else { return false }
            perform(key.action, in: document)
        case .cursor(let offset):
            moveCursor(by: offset, in: document)
        case .cursorLines(let count):
            moveCursor(lines: count, in: document)
        case .oneHanded(let hand):
            settings.oneHanded = hand
        case .pick(let hand):
            settings.oneHanded = hand
            perform(.layer(.letters), in: document)
        case .split(let split):
            settings.split = split
            perform(.layer(.letters), in: document)
        case .settings, .nextKeyboard, .keep:
            perform(.layer(.letters), in: document)
        case .panel(let panel):
            show(panel)
        case .emoji(let emoji, let base):
            emojiHistory.use(emoji, base: base)
            insertWhole(emoji, in: document)
        case .paste(let text):
            insertWhole(text, in: document)
        case .dictated(let heard):
            let lexicon = corrector?.lexicon
            let capitals = settings.dictation.capitals(in: traits.autocapitalization)
            insertWhole(in: document) { Self.fitted(heard, between: $0.before, and: $0.after, lexicon: lexicon, capitals: capitals) }
        }
        return true
    }

    public mutating func deleteWord(in document: some TextDocument) {
        if panel != nil, !query.isEmpty {
            query = String(query.dropLast(Self.wordLength(before: query)))
            return suggestionsChanged()
        }
        if panel != nil, deleteHeldInSearch { return }
        attach(document)
        lastSpace = nil
        revert = nil
        if typing.letters.isEmpty, let pending {
            let head = Substring(text.before).dropLast(while: { !Words.isWordCharacter($0) })
            if head.hasSuffix(pending.word) {
                corrector?.forget(pending.word, after: Words.previous(before: Words.current(in: String(head)), in: String(head)))
            }
            self.pending = nil
        }
        typing = WordTaps()
        write("", replacing: Self.wordLength(before: text.before), in: document)
        refreshShift()
        suggestionsChanged()
    }

    /// Text that arrives whole, an emoji or what dictation heard: it ends the word in progress, then goes in as it is.
    mutating func insertWhole(_ string: String, in document: some TextDocument) {
        insertWhole(in: document) { _ in string }
    }

    /// Text that arrives whole, made from the text as it is once the word in progress has ended.
    mutating func insertWhole(in document: some TextDocument, _ string: (TextState) -> String) {
        attach(document)
        lastSpace = nil
        revert = nil
        commitWord(in: document)
        write(string(text), in: document)
        refreshShift()
        suggestionsChanged()
    }

    /// Moves the caret, as the space bar trackpad does.
    mutating func moveCursor(by offset: Int, in document: some TextDocument) {
        guard panel == nil else { return }
        attach(document)
        lineGoal = nil
        moveCaret(by: offset, in: document)
        forgetWord()
        refreshShift()
        suggestionsChanged()
    }

    /// The character the caret would cross moving one step, -1 left or 1 right, when the engine knows the text there.
    public func character(crossedBy step: Int) -> Character? {
        guard panel == nil, text.isKnown else { return nil }
        return step < 0 ? text.before.last : text.after?.first
    }

    mutating func moveCaret(by offset: Int, in document: some TextDocument) {
        document.moveCursor(by: offset)
        text.moveCursor(by: offset)
    }

    /// Moves the caret down `count` lines, up when negative, as the space bar trackpad does.
    mutating func moveCursor(lines count: Int, in document: some TextDocument) {
        guard panel == nil, let lineLayout else { return }
        attach(document)
        guard text.isKnown else { return }
        let move = Lines.move(count, before: text.before, after: text.after ?? "", goal: lineGoal, layout: lineLayout)
        if move.offset != 0 { moveCursor(by: move.offset, in: document) }
        lineGoal = move.goal
    }

    mutating func pressShift(doubleTap: Bool) {
        shift = doubleTap && settings.capsLock ? .locked : shift == .off ? .on : .off
        shiftHold = .pressed
    }

    mutating func releaseShift(in document: some TextDocument) {
        let typed = shiftHold == .typedWhileHeld
        shiftHold = nil
        guard typed, shift == .on else { return }
        attach(document)
        refreshShift()
    }

    /// The keys while a panel is open: they edit its search, and return closes it. Delete with the search empty deletes
    /// in the app, so a wrong pick can be undone without leaving the panel.
    private mutating func search(_ action: KeyAction) {
        switch action {
        case .character(let key):
            query += shift.isUppercase && layer == .letters ? key.uppercased() : key
            if Self.returnsToLetters.contains(key) { layer = .letters }
        case .space:
            query += " "
            layer = .letters
        case .delete:
            query = String(query.dropLast())
        case .return:
            return show(nil)
        default:
            return
        }
        if shiftHold != nil { shiftHold = .typedWhileHeld }
        refreshShift()
        suggestionsChanged()
    }

    /// Opens a panel, or closes it with nil, which brings back the keys the field opens with.
    private mutating func show(_ panel: Panel?) {
        if panel != nil {
            layer = .letters
        } else if self.panel != nil {
            layer = Self.initialLayer(for: traits.kind)
        }
        self.panel = panel
        query = ""
        refreshShift()
        suggestionsChanged()
    }

    /// Learns from the last words you kept, the one in progress too. Call when the keyboard goes away.
    public mutating func endSession() {
        guard !sessionEnded else { return }
        keepWord(in: text)
        typing = WordTaps()
        sessionEnded = true
    }

    /// Finish learning in the old app before adopting another host’s field and language.
    public mutating func changeApp(_ app: String?) {
        guard corrector?.app != app else { return }
        endSession()
        text = TextState()
        forgetWord()
        sessionEnded = false
        corrector?.app = app
        suggestionsChanged()
    }

    /// The host's `textDidChange` or `selectionDidChange`. A report showing the keyboard's own edits, even late, changes
    /// nothing; anything else replaces what the engine knows and forgets the word in progress. An emptied field was
    /// sent, so its last words were kept, the one in progress too.
    @discardableResult
    public mutating func documentChanged(_ document: some TextDocument) -> TextState.Report {
        let known = text
        let report = text.reconcile(before: document.textBeforeInput, after: document.textAfterInput, selected: document.selectedText)
        if report == .changed {
            if text.isEmpty, !sessionEnded { keepWord(in: known) }
            sessionEnded = false
            forgetWord()
        }
        if report == .changed || text.before != known.before || text.after != known.after || text.selected != known.selected {
            refreshShift()
            suggestionsChanged()
        }
        if let goal = lineGoal, goal.landing == nil { moveCursor(lines: 0, in: document) }
        return report
    }

    mutating func refreshShift() {
        guard shift != .locked, shiftHold == nil else { return }
        guard panel == nil else { return shift = .off }
        let mode = settings.autoCapitalization ? traits.autocapitalization : .none
        let capitalize = layer == .letters && Self.shouldCapitalize(text.before, mode: mode)
        shift = capitalize ? .on : .off
    }

    /// The one way text changes: deletes `count` characters before the caret, then inserts `string`, in the host and
    /// in `text` alike.
    mutating func write(_ string: String, replacing count: Int = 0, in document: some TextDocument) {
        sessionEnded = false
        lineGoal = nil
        if count > 0 {
            document.deleteBackward(count)
            text.deleteBackward(count)
        }
        if !string.isEmpty {
            document.insert(string)
            text.insert(string)
        }
    }

    /// Reads the host once, the first time the engine meets it.
    mutating func attach(_ document: some TextDocument) {
        guard !text.isKnown else { return }
        text.reconcile(before: document.textBeforeInput, after: document.textAfterInput, selected: document.selectedText)
    }

    private mutating func forgetWord() {
        lastSpace = nil
        pending = nil
        typing = WordTaps()
        stray = nil
        revert = nil
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

    /// What dictation heard, fitted between the text around the caret. The speech model writes every dictation as
    /// sentences of their own, so one that goes into the middle of a sentence starts lowercase (unless the lexicon
    /// spells its first word capitalized, as a name or "I"), and loses its final period when the sentence goes on after
    /// it. Its capitals follow the field's and Auto-Capitalization's, as typing's do: with none, a sentence's first word
    /// is lowered where the lexicon spells it lowercase, and so is "I", leaving names; with sentences, each sentence starts
    /// with a capital. It's spaced from the words on either side.
    static func fitted(_ heard: String, between before: String, and after: String?, lexicon: Lexicon?, capitals: Autocapitalization) -> String {
        var heard = Array(heard)
        let last = before.last { $0 != " " && $0 != "\t" && !closers.contains($0) }
        let startsSentence = last.map { $0.isNewline || sentenceEnders.contains($0) } ?? true
        for (index, start) in sentenceStarts(in: heard).enumerated() {
            let word = String(heard[start...].prefix(while: Words.isWordCharacter))
            let opensSentence = index > 0 || startsSentence
            if !opensSentence || capitals == .none {
                if word.dropFirst() == word.lowercased().dropFirst(), lexicon?.canonical(word) == word.lowercased() {
                    heard[start] = Character(heard[start].lowercased())
                }
            } else if capitals == .sentences, word == word.lowercased() {
                heard[start] = Character(heard[start].uppercased())
            }
        }
        if capitals == .none {
            for word in Words.ranges(in: heard) where spellsI(heard[word]) { heard[word.lowerBound] = "i" }
        }
        var fitted = String(heard)
        if let next = after?.first, !next.isWhitespace {
            if next.isLowercase || wordEnders.contains(String(next)), fitted.hasSuffix("."), !fitted.hasSuffix("..") {
                fitted.removeLast()
            }
            if !wordEnders.contains(String(next)), !closers.contains(next) { fitted += " " }
        }
        let joins = before.last.map { !$0.isWhitespace && !Words.openers.contains($0) } ?? false
        return (joins ? " " : "") + fitted
    }

    /// Where each sentence's first word starts in dictated text: at its start, and after a period, question mark,
    /// exclamation mark or line break, past any spaces and openers.
    private static func sentenceStarts(in text: [Character]) -> [Int] {
        var starts: [Int] = []
        var expecting = true
        for (at, character) in text.enumerated() {
            if expecting, Words.isWordCharacter(character) {
                if character.isLetter { starts.append(at) }
                expecting = false
            } else if character.isNewline || sentenceEnders.contains(character) && (at + 1 == text.count || text[at + 1].isWhitespace) {
                expecting = true
            } else if expecting, !character.isWhitespace, !Words.openers.contains(character) {
                expecting = false
            }
        }
        return starts
    }

    private static func spellsI(_ word: ArraySlice<Character>) -> Bool {
        guard word.first == "I" else { return false }
        let rest = word.dropFirst()
        return rest.isEmpty || ["'", "’"].contains(rest.first) && ["m", "ll", "ve", "d"].contains(String(rest.dropFirst()))
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
