/// The words you say that the speech model doesn't know, each with what it writes instead. In a dictation, a listed
/// spelling or the term written another way ("tail scale", "TailScale") becomes the term. Only whole words match, up
/// to four, ignoring case, spaces and hyphens, never across punctuation or inside a name or path, longest first, and a
/// possessive keeps its "'s".
///
/// With a lexicon, a made-up word the model writes that sounds like a term becomes it too ("kestrul dot run" for
/// kestrel.run, "IKB" for iikb), as do words like those already in the field (`field`), so a name written once comes out
/// the same when said again. A real word is only swapped if it's listed, so "sound" stays unless "Astound" lists it. A
/// name with digits after it, as in an address ("tamsen101"), is matched by its name and keeps its digits.
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

    public func corrected(_ text: String, lexicon: Lexicon? = nil, field: String = "") -> String {
        var spellings: [String: String] = [:]
        for term in terms {
            for spelling in [term.term] + term.heardAs where !Self.key(spelling).isEmpty {
                spellings[Self.key(spelling)] = term.term
            }
        }
        let soundsLike = lexicon.map { lexicon in
            terms.flatMap { term in ([term.term] + term.heardAs).map { Likeness($0, term: term.term, seen: false) } }
                + Self.seen(in: field, lexicon: lexicon).map { Likeness($0, term: $0, seen: true) }
        } ?? []
        guard !spellings.isEmpty || !soundsLike.isEmpty else { return text }
        let characters = Array(text)
        let words = Words.ranges(in: characters)
        var result = ""
        var copied = 0
        var index = 0
        while index < words.count {
            var matched = false
            for count in stride(from: min(5, words.count - index), through: 1, by: -1) {
                let span = words[index ..< index + count]
                let start = span.first!.lowerBound, end = span.last!.upperBound
                let gaps = span.dropLast().indices.map { String(characters[words[$0].upperBound ..< words[$0 + 1].lowerBound]) }
                var term: String?
                var possessive = ""
                if count <= 4, gaps.allSatisfy({ $0.allSatisfy { $0 == " " || $0 == "-" } }),
                   !Self.isGlued(characters, before: start, after: end, by: Self.glue) {
                    var said = String(characters[start ..< end])
                    if spellings[Self.key(said)] == nil, let last = said.last, last == "s" || last == "S",
                       let mark = said.dropLast().last, mark == "'" || mark == "’" {
                        possessive = String(said.suffix(2))
                        said = String(said.dropLast(2))
                    }
                    term = spellings[Self.key(said)]
                }
                if term == nil, let lexicon, gaps.allSatisfy({ $0 == " " || $0 == "-" || $0 == "." }),
                   !Self.isGlued(characters, before: start, after: end, by: Self.glue.subtracting(["."])) {
                    possessive = ""
                    term = Self.soundsLike(span.map { String(characters[$0]) }, said: String(characters[start ..< end]),
                                           in: soundsLike, lexicon: lexicon)
                }
                if term == nil, count == 1, let (name, number) = Self.numbered(String(characters[start ..< end])),
                   !Self.isGlued(characters, before: start, after: end, by: Self.glue.subtracting(["@"])) {
                    possessive = ""
                    term = (spellings[Self.key(name)] ?? lexicon.flatMap { Self.soundsLike([name], said: name, in: soundsLike, lexicon: $0) })
                        .map { $0 + number }
                }
                guard let term else { continue }
                var from = start
                if term.contains("."), let joined = Self.spokenDot(before: start, in: characters), joined >= copied {
                    from = joined
                    result += String(characters[copied ..< from]) + "."
                } else {
                    result += String(characters[copied ..< start])
                }
                result += term + possessive
                copied = end
                index += count
                matched = true
                break
            }
            if !matched { index += 1 }
        }
        return result + String(characters[copied...])
    }

    /// A spelling a made-up word can sound like, and the term it stands for. `seen` is one read off the field, which
    /// leaves a word that only adds an ending to it ("subagents" by "subagent") or only changes its case.
    struct Likeness {
        let key: [Character]
        let words: Set<String>
        let term: String
        let seen: Bool

        init(_ spelling: String, term: String, seen: Bool) {
            let said = Array(Vocabulary.saying(spelling).lowercased())
            key = Array(Vocabulary.key(String(said)))
            words = Set(Words.ranges(in: said).map { String(said[$0]) })
            self.term = term
            self.seen = seen
        }

        /// How many letters may differ: none under four, one up to six, two up to twelve, three past that.
        var slack: Int {
            switch key.count {
            case ..<4: 0
            case ...6: 1
            case ...12: 2
            default: 3
            }
        }
    }

    /// The closest term to a span with a word the lexicon lacks, starting with the same sound and ending in words it
    /// owns, so "Wispr Flow or" never takes the "or".
    private static func soundsLike(_ words: [String], said: String, in likenesses: [Likeness], lexicon: Lexicon) -> String? {
        let real = words.map { lexicon.isWord(Words.plain($0)) }
        guard real.contains(false), !words.contains(where: { $0.allSatisfy(\.isNumber) }) else { return nil }
        let key = Array(spoken(said))
        guard key.count >= 3 else { return nil }
        var best: (distance: Int, term: String)?
        for likeness in likenesses where likeness.slack > 0 && likeness.key.first == key.first {
            guard abs(likeness.key.count - key.count) <= likeness.slack else { continue }
            guard !real.first! || likeness.words.contains(words.first!.lowercased()),
                  !real.last! || likeness.words.contains(words.last!.lowercased()) else { continue }
            if likeness.seen, key.starts(with: likeness.key) || likeness.key.starts(with: key) { continue }
            let distance = distance(key, likeness.key)
            if distance <= likeness.slack, distance < best?.distance ?? .max { best = (distance, likeness.term) }
        }
        guard let best, best.term != said else { return nil }
        return best.term
    }

    /// Words in the field worth matching a dictation to: each name with a dot in it, from each of its parts to its end
    /// ("proxy.kestrel.run", "kestrel.run"), and each word of four letters or more the lexicon lacks.
    static func seen(in field: String, lexicon: Lexicon) -> Set<String> {
        let characters = Array(field)
        var seen: Set<String> = []
        var name: [Range<Int>] = []
        func close() {
            if name.count > 1 {
                for from in name.indices.dropLast() {
                    seen.insert(String(characters[name[from].lowerBound ..< name.last!.upperBound]))
                }
            }
            name = []
        }
        for word in Words.ranges(in: characters) {
            let spelled = String(characters[word])
            if spelled.count >= 4, !spelled.allSatisfy(\.isNumber), !lexicon.isWord(Words.plain(spelled)) { seen.insert(spelled) }
            if let last = name.last, characters[last.upperBound ..< word.lowerBound] == ["."] {
                name.append(word)
            } else {
                close()
                name = [word]
            }
        }
        close()
        return seen.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
    }

    /// A name with digits after it, as the model writes one in an address ("Tamsen101"), apart.
    private static func numbered(_ word: String) -> (name: String, number: String)? {
        let name = word.prefix { $0.isLetter }, number = word.dropFirst(name.count)
        guard !name.isEmpty, !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return (String(name), String(number))
    }

    /// Where "<word> dot " starts its dot, right before `start`, so a spoken dot joins a name with a dot in it.
    private static func spokenDot(before start: Int, in characters: [Character]) -> Int? {
        let dot = Array(" dot ")
        guard start >= dot.count + 1,
              String(characters[start - dot.count ..< start]).lowercased() == " dot ",
              Words.isWordCharacter(characters[start - dot.count - 1]) else { return nil }
        return start - dot.count
    }

    static let glue: Set<Character> = ["-", "/", "\\", "_", "@", ".", ":"]

    /// Whether the words are part of a name or path written with the words around them, as in "comet-kvm-codex" or
    /// "openai/codex", which stay as written.
    private static func isGlued(_ characters: [Character], before start: Int, after end: Int, by glue: Set<Character>) -> Bool {
        let left = start >= 2 && glue.contains(characters[start - 1]) && Words.isWordCharacter(characters[start - 2])
        let right = end + 1 < characters.count && glue.contains(characters[end]) && Words.isWordCharacter(characters[end + 1])
        return left || right
    }

    static func key(_ spelling: some StringProtocol) -> String {
        String(spelling.lowercased().filter { $0 != " " && $0 != "-" })
    }

    /// A spelling as it's said, its dots as "dot".
    static func saying(_ spelling: some StringProtocol) -> String {
        String(spelling.flatMap { $0 == "." ? Array(" dot ") : [$0] })
    }

    private static func spoken(_ spelling: some StringProtocol) -> String {
        key(saying(spelling))
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0 ... b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1]
            for (j, y) in b.enumerated() {
                row.append(min(previous[j] + (x == y ? 0 : 1), previous[j + 1] + 1, row[j] + 1))
            }
            previous = row
        }
        return previous[b.count]
    }
}
