public struct TypingEngine: Sendable {
    public private(set) var layer: KeyboardLayer = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var traits: InputTraits

    private var spaceJustTyped = false
    private var shiftHold: ShiftHold?

    private enum ShiftHold { case pressed, typedWhileHeld }

    public init(traits: InputTraits = InputTraits()) {
        self.traits = traits
        self.layer = Self.initialLayer(for: traits.kind)
    }

    public mutating func update(_ traits: InputTraits) {
        if traits.kind != self.traits.kind { layer = Self.initialLayer(for: traits.kind) }
        self.traits = traits
    }

    public mutating func perform(_ action: KeyAction, in document: some TextDocument) {
        let wasSpace = spaceJustTyped
        spaceJustTyped = false

        switch action {
        case .character(let text):
            document.insert(shift.isUppercase && layer == .letters ? text.uppercased() : text)
            if layer != .letters, Self.returnsToLetters.contains(text) { layer = .letters }
            if shiftHold != nil { shiftHold = .typedWhileHeld }
        case .space:
            if wasSpace, traits.smartPunctuation, Self.endsSentenceable(document.textBeforeInput) {
                document.deleteBackward(1)
                document.insert(". ")
            } else {
                document.insert(" ")
                spaceJustTyped = true
            }
            if layer != .letters { layer = .letters }
        case .return:
            document.insert("\n")
        case .tab:
            document.insert("\t")
        case .delete:
            document.deleteBackward(1)
        case .shift:
            shift = shift == .off ? .on : .off
            return
        case .capsLock:
            shift = shift == .locked ? .off : .locked
            return
        case .layer(let target):
            layer = target
            return
        case .nextKeyboard, .dismiss:
            return
        }
        refreshShift(in: document)
    }

    public mutating func deleteWord(in document: some TextDocument) {
        spaceJustTyped = false
        document.deleteBackward(Self.wordLength(before: document.textBeforeInput))
        refreshShift(in: document)
    }

    public mutating func pressShift(doubleTap: Bool) {
        shift = doubleTap ? .locked : shift == .off ? .on : .off
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
        refreshShift(in: document)
    }

    public mutating func refreshShift(in document: some TextDocument) {
        guard shift != .locked, shiftHold == nil else { return }
        let capitalize = layer == .letters && Self.shouldCapitalize(document.textBeforeInput, mode: traits.autocapitalization)
        shift = capitalize ? .on : .off
    }
}

extension TypingEngine {
    static let returnsToLetters: Set<String> = ["'"]
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
