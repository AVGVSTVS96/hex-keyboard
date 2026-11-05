/// The words you say that the speech model doesn't know, each with what it writes instead. In a dictation, a listed
/// spelling or the term written another way ("tail scale", "TailScale") becomes the term. Only whole words match, up
/// to four, ignoring case, spaces and hyphens, never across punctuation or inside a name or path, longest first, and a
/// possessive keeps its "'s". Nothing is guessed: a word the model writes that isn't listed stays, so a real word you
/// also say ("sound" for "Astound") is only swapped if you list it.
public struct Vocabulary: Codable, Equatable, Sendable {
    public struct Term: Codable, Equatable, Hashable, Sendable {
        public var term: String
        public var heardAs: [String]

        public init(_ term: String, heardAs: [String] = []) {
            self.term = term
            self.heardAs = heardAs
        }
    }

    public var terms: [Term]

    public init(_ terms: [Term] = []) {
        self.terms = terms
    }

    public func corrected(_ text: String) -> String {
        var spellings: [String: String] = [:]
        for term in terms {
            for spelling in [term.term] + term.heardAs where !Self.key(spelling).isEmpty {
                spellings[Self.key(spelling)] = term.term
            }
        }
        guard !spellings.isEmpty else { return text }
        let characters = Array(text)
        let words = Words.ranges(in: characters)
        var result = ""
        var copied = 0
        var index = 0
        while index < words.count {
            var matched = false
            for count in stride(from: min(4, words.count - index), through: 1, by: -1) {
                let span = words[index ..< index + count]
                let joins = span.dropLast().indices.allSatisfy { at in
                    characters[words[at].upperBound ..< words[at + 1].lowerBound].allSatisfy { $0 == " " || $0 == "-" }
                }
                guard joins, !Self.isGlued(characters, before: span.first!.lowerBound, after: span.last!.upperBound) else { continue }
                var said = String(characters[span.first!.lowerBound ..< span.last!.upperBound])
                var possessive = ""
                if spellings[Self.key(said)] == nil, let last = said.last, last == "s" || last == "S",
                   let mark = said.dropLast().last, mark == "'" || mark == "’" {
                    possessive = String(said.suffix(2))
                    said = String(said.dropLast(2))
                }
                guard let term = spellings[Self.key(said)] else { continue }
                result += String(characters[copied ..< span.first!.lowerBound]) + term + possessive
                copied = span.last!.upperBound
                index += count
                matched = true
                break
            }
            if !matched { index += 1 }
        }
        return result + String(characters[copied...])
    }

    /// Whether the words are part of a name or path written with the words around them, as in "comet-kvm-codex" or
    /// "openai/codex", which stay as written.
    private static func isGlued(_ characters: [Character], before start: Int, after end: Int) -> Bool {
        let glue: Set<Character> = ["-", "/", "\\", "_", "@", ".", ":"]
        let left = start >= 2 && glue.contains(characters[start - 1]) && Words.isWordCharacter(characters[start - 2])
        let right = end + 1 < characters.count && glue.contains(characters[end]) && Words.isWordCharacter(characters[end + 1])
        return left || right
    }

    private static func key(_ spelling: some StringProtocol) -> String {
        String(spelling.lowercased().filter { $0 != " " && $0 != "-" })
    }
}
