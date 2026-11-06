/// The words you say that the speech model doesn't know, each with what it writes instead. In a dictation, a listed
/// spelling or the term written another way ("tail scale", "TailScale") becomes the term. Only whole words match, up
/// to four, ignoring case, spaces and hyphens, never across punctuation or inside a name or path, longest first, and a
/// possessive keeps its "'s".
///
/// With a lexicon, a made-up word the model writes that sounds like a term becomes it too ("kestrul dot run" for
/// kestrel.run, "IKB" for iikb), as do words like those already in the field (`field`), so a name written once comes out
/// the same when said again. A word you type often (`typed`) is taken only for one the model wrote that doesn't look
/// like a name ("OPIS", "IKB", "AutoFour") or in an address: a word written as a name ("Bassam", "Nira") is likelier
/// a name you said than one you type, and so is any word you've typed yourself. A real word is only swapped if it's listed, so "sound" stays unless "Astound" lists it. A
/// name with digits after it, as in an address ("tamsen101"), is matched by its name and keeps its digits, and so is
/// a name with none ("Renner at fastmail.com").
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

    /// The words you type: the ones a dictation may become (`often`) and every one you've typed twice or more (`own`),
    /// which none of them replaces.
    public struct Typed: Equatable, Sendable {
        public var often: Set<String>
        public var own: Set<String>

        public init(often: Set<String> = [], own: Set<String> = []) {
            self.often = often
            self.own = own
        }
    }

    public init(_ terms: [Term] = []) {
        self.terms = terms
    }

    public func corrected(_ text: String, lexicon: Lexicon? = nil, field: String = "", typed: Typed = Typed()) -> String {
        var spellings: [String: String] = [:]
        for term in terms {
            for spelling in [term.term] + term.heardAs where !Self.key(spelling).isEmpty {
                spellings[Self.key(spelling)] = term.term
            }
        }
        let soundsLike = lexicon.map { lexicon in
            terms.flatMap { term in ([term.term] + term.heardAs).map { Likeness($0, term: term.term, seen: false) } }
                + Self.seen(in: field, lexicon: lexicon).map { Likeness($0, term: $0, seen: true) }
                + typed.often.map { Likeness($0, term: $0, seen: true, cased: true) }
        } ?? []
        let unlike = soundsLike.filter { !$0.cased }
        let typable = { (words: [String]) in words.allSatisfy { !Self.isTitled($0) && !typed.own.contains($0.lowercased()) } }
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
                    let said = span.map { String(characters[$0]) }
                    term = Self.soundsLike(said, said: String(characters[start ..< end]), in: typable(said) ? soundsLike : unlike, lexicon: lexicon)
                }
                if term == nil, count == 1, let (name, number) = Self.numbered(String(characters[start ..< end])) ?? Self.addressed(characters, start ..< end),
                   !Self.isGlued(characters, before: start, after: end, by: Self.glue.subtracting(["@"])) {
                    possessive = ""
                    let likely = typed.own.contains(name.lowercased()) ? unlike
                        : number.isEmpty ? soundsLike.filter { !$0.cased || lexicon?.isWord($0.term.lowercased()) == false } : soundsLike
                    term = (spellings[Self.key(name)] ?? lexicon.flatMap { Self.soundsLike([name], said: name, in: likely, lexicon: $0, address: true) })
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

    /// A spelling a made-up word can sound like, and the term it stands for. `seen` is one read off the field or your
    /// typing, which leaves a word that only adds an ending to it ("subagents" by "subagent") or only changes its case;
    /// `cased`, one from your typing, takes the capital the model gave the word.
    struct Likeness {
        let key: [Character]
        let sound: [Character]
        let words: Set<String>
        let term: String
        let seen: Bool
        var cased = false

        init(_ spelling: String, term: String, seen: Bool, cased: Bool = false) {
            let said = Array(Vocabulary.saying(spelling).lowercased())
            key = Array(Vocabulary.key(String(said)))
            sound = Vocabulary.sound(key)
            words = Set(Words.ranges(in: said).map { String(said[$0]) })
            self.term = term
            self.seen = seen
            self.cased = cased
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
    /// owns, so "Wispr Flow or" never takes the "or", by its letters or by how they sound ("odallis" for Odalys,
    /// "kaspian" for Caspian), and by one letter more for the name in an address, where a name is all it can be.
    private static func soundsLike(_ words: [String], said: String, in likenesses: [Likeness], lexicon: Lexicon, address: Bool = false) -> String? {
        let real = words.map { lexicon.isWord(Words.plain($0)) }
        guard real.contains(false), !words.contains(where: { $0.allSatisfy(\.isNumber) }) else { return nil }
        let key = Array(spoken(said)), sound = Self.sound(key)
        guard key.count >= 3 else { return nil }
        var best: (distance: Int, term: String, cased: Bool)?
        for likeness in likenesses where likeness.slack > 0 && (likeness.key.first == key.first || likeness.sound.first == sound.first) {
            let slack = likeness.slack + (address ? 1 : 0)
            guard abs(likeness.key.count - key.count) <= slack else { continue }
            guard !real.first! || likeness.words.contains(words.first!.lowercased()),
                  !real.last! || likeness.words.contains(words.last!.lowercased()) else { continue }
            if likeness.seen, key.starts(with: likeness.key) || likeness.key.starts(with: key) { continue }
            let distance = min(distance(key, likeness.key), distance(sound, likeness.sound))
            if distance <= slack, distance < best?.distance ?? .max { best = (distance, likeness.term, likeness.cased) }
        }
        guard let best, best.term != said else { return nil }
        guard best.cased, isTitled(said), best.term == best.term.lowercased() else { return best.term }
        return best.term.prefix(1).uppercased() + best.term.dropFirst()
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

    /// A word that's the name in an address said after it ("Renner at fastmail.com"), as a name with no digits, which
    /// a word you type often becomes only if it's made up ("corvena" is corvina, but "lyri" isn't LIKE).
    private static func addressed(_ characters: [Character], _ word: Range<Int>) -> (name: String, number: String)? {
        let name = String(characters[word])
        guard name.allSatisfy(\.isLetter), SpokenAddress.startsHost(String(characters[word.upperBound...])) else { return nil }
        return (name, "")
    }

    /// A name with digits after it, as the model writes one in an address ("Tamsen101"), apart.
    private static func numbered(_ word: String) -> (name: String, number: String)? {
        let name = word.prefix { $0.isLetter }, number = word.dropFirst(name.count)
        guard !name.isEmpty, !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return (String(name), String(number))
    }

    /// The words you type (`Typed`), read from a memory once and then kept up to date a word at a time, so a dictation
    /// never scans the memory. Often: each of four letters or more typed five times or more that the lexicon lacks
    /// ("iikb"), as you spell it most, or that you've capitalized after another word three times or more ("Opus"), so a
    /// sentence's first word ("Also") isn't one, spelled with that capital.
    public struct TypedIndex {
        public private(set) var typed = Typed()
        private var spellings: [String: [String: Int]] = [:]
        private var capitals: [String: Int] = [:]
        private let lexicon: Lexicon

        public init(_ memory: TypingMemory, lexicon: Lexicon) {
            self.lexicon = lexicon
            for (word, count) in memory.counts where Self.counts(word) {
                spellings[word.lowercased(), default: [:]][word] = count
            }
            for (previous, next) in memory.following where !previous.isEmpty && !previous.contains(" ") {
                for (word, count) in next where word.first?.isUppercase == true { capitals[word, default: 0] += count }
            }
            typed.own = Set(memory.counts.filter { $0.value >= 2 }.keys.map { $0.lowercased() })
            for lowered in spellings.keys { refresh(lowered) }
        }

        /// One more of `word` after `previous`, as `TypingMemory.record` counts it, which now has it `count` times.
        public mutating func record(_ word: String, after previous: String?, count: Int) {
            let word = Words.plain(word)
            if count >= 2 { typed.own.insert(word.lowercased()) }
            if let previous, !Words.plain(previous).isEmpty, word.first?.isUppercase == true { capitals[word, default: 0] += 1 }
            guard Self.counts(word) else { return }
            spellings[word.lowercased(), default: [:]][word, default: 0] += 1
            refresh(word.lowercased())
        }

        private mutating func refresh(_ lowered: String) {
            let spellings = spellings[lowered] ?? [:]
            typed.often.subtract(spellings.keys)
            guard spellings.values.reduce(0, +) >= 5 else { return }
            let often = lexicon.isWord(lowered) ? spellings.keys.filter { capitals[$0, default: 0] >= 3 }.max { (capitals[$0]!, $1) < (capitals[$1]!, $0) }
                : spellings.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
            if let often { typed.often.insert(often) }
        }

        private static func counts(_ word: String) -> Bool {
            word.count >= 4 && word.allSatisfy(\.isLetter)
        }
    }

    /// Whether a word is written as a name is: a capital, then lowercase ("Nira", not "OPIS" or "AutoFour").
    private static func isTitled(_ word: String) -> Bool {
        word.count > 1 && word.first!.isUppercase && word.dropFirst().allSatisfy { !$0.isUppercase }
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

    /// Letters as they sound, roughly: a silent first w or k ("wr", "kn") gone, ph as f, ck as k, c as s before e, i
    /// or y and as k otherwise, g as j before e or i, y as i after the first letter, and each doubled letter once.
    static func sound(_ key: [Character]) -> [Character] {
        var key = key
        if key.count > 2, key[1] == "r" && key[0] == "w" || key[1] == "n" && key[0] == "k" { key.removeFirst() }
        var sound: [Character] = []
        var at = 0
        while at < key.count {
            let letter = key[at], next = at + 1 < key.count ? key[at + 1] : nil
            var heard: Character = letter
            switch letter {
            case "p" where next == "h": heard = "f"; at += 1
            case "c" where next == "k": heard = "k"; at += 1
            case "c": heard = next.map { "eiy".contains($0) } == true ? "s" : "k"
            case "g" where next.map { "ei".contains($0) } == true: heard = "j"
            case "y" where at > 0: heard = "i"
            default: break
            }
            if sound.last != heard { sound.append(heard) }
            at += 1
        }
        return sound
    }

    private static func spoken(_ spelling: some StringProtocol) -> String {
        key(saying(spelling))
    }

    static func distance(_ a: [Character], _ b: [Character]) -> Int {
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
