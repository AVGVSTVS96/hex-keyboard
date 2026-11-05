/// An address you speak, written as one: "John dot Smith at Gmail dot com." becomes "john.smith@gmail.com", and
/// "w w w dot example dot com slash pricing" "www.example.com/pricing". The words for the signs an address has (at, dot,
/// underscore, dash, hyphen, slash, colon) become them, number words and spoken digit runs become digits ("twenty
/// one", "one two three", "oh" beside digits as 0), the spaces go, and so does the closing period. It is the same
/// spoken form Apple's, Gboard's and NVIDIA NeMo's dictation read, and nothing is listed per person. Only the first
/// "at" is the sign, since an address has one.
enum SpokenAddress {
    private enum Piece: Equatable {
        case symbol(String)
        case number(String)
        case word(String)
    }

    private static let signs = ["at": "@", "dot": ".", "underscore": "_", "dash": "-", "hyphen": "-", "slash": "/", "colon": ":"]
    private static let joiners: Set<String> = ["dot", "underscore", "dash", "hyphen"]
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                                "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    private static let domains: Set<String> = ["com", "org", "net", "edu", "gov", "io", "co", "us", "uk", "ai", "app", "dev", "me", "info", "tv", "ca", "de", "fr", "run"]
    private static let determiners: Set<String> = ["the", "a", "an", "this", "that", "my", "your", "our", "his", "her", "their", "its"]

    /// What `said` spells as an address, or nil when it says nothing.
    static func read(_ said: String) -> String? {
        var text = ""
        var at = false
        for piece in pieces(said) {
            switch piece {
            case .symbol("at") where at: text += "at"
            case .symbol(let sign): at = at || sign == "at"; text += signs[sign]!
            case .number(let digits): text += digits
            case .word(let word): text += word
            }
        }
        return text.isEmpty ? nil : text
    }

    /// What `said` spells when all of it is a web address or an email's domain, as in a search field: an address has no
    /// two plain words in a row ("how to reach example dot com" is a question about one).
    static func domain(_ said: String) -> String? {
        let pieces = pieces(said)
        let plain = pieces.map { piece -> Bool in
            if case .word(let word) = piece { return word.count > 1 }
            return false
        }
        guard !zip(plain, plain.dropFirst()).contains(where: { $0 && $1 }), let address = read(said) else { return nil }
        return address.wholeMatch(of: /(https?:\/\/)?([a-z0-9_.+-]+@)?([a-z0-9-]+\.)+[a-z]{2,}(\/\S*)?/) == nil ? nil : address
    }

    /// The digits `said` says: number words, digit runs and the digits in what the model wrote ("555-1234"), and nothing
    /// else but a "+" it starts with ("plus one ...") and, in a field that takes one (`point`), the first decimal point,
    /// said or written; nil when there are no digits.
    static func digits(_ said: String, point: Bool = false) -> String? {
        var digits = ""
        var pointed = !point
        for piece in pieces(said, zeros: ["oh", "o"]) {
            switch piece {
            case .number(let number): digits += number
            case .word("plus") where digits.isEmpty: digits = "+"
            case .word("point") where !pointed && !digits.isEmpty: digits += "."; pointed = true
            case .word(let word):
                for character in word {
                    if character.isNumber { digits.append(character) }
                    else if character == "+", digits.isEmpty { digits = "+" }
                    else if character == ".", !pointed, digits.last?.isNumber == true { digits += "."; pointed = true }
                }
            case .symbol: break
            }
        }
        while let last = digits.last, !last.isNumber { digits.removeLast() }
        return digits.isEmpty ? nil : digits
    }

    /// `text` with an address spoken inside it written as one (`emails`, then `webAddresses`).
    static func inline(_ text: String) -> String {
        webAddresses(emails(text))
    }

    /// `text` with an email address spoken inside it written as one, found by its domain: after an "at", a domain with
    /// its ending, spoken ("email me at john at gmail dot com" is "email me at john@gmail.com") or written, when the name
    /// before the "at" has a dot, underscore, dash or digit in it ("jane.doe at gmail.com"), since "shop at example.com"
    /// is a sentence. Text that isn't one is returned as it is.
    private static func emails(_ text: String) -> String {
        guard text.contains(" at ") else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var from = 0
        while let at = words[from...].firstIndex(where: { clean($0) == "at" }) {
            from = at + 1
            guard let host = host(in: words, after: at), let local = local(in: words, before: at) else { continue }
            let name = words[local ..< at].compactMap { read($0) }.joined()
            guard host.spoken || name.contains(where: { "._-".contains($0) || $0.isNumber }) else { continue }
            let address = name + "@" + host.name
            words.replaceSubrange(local ..< host.end, with: [address + host.tail])
            from = local + 1
        }
        return words.joined(separator: " ")
    }

    /// `text` with a web address spoken in it written as one, found by its ending ("open Kestrel dot run" is "open
    /// kestrel.run"), though never at or after "the" or "my" ("the dot com bubble", "at the park dot com is down").
    private static func webAddresses(_ text: String) -> String {
        guard text.contains(" dot ") || text.contains(" Dot ") else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var at = 0
        while at < words.count {
            if !determiners.contains(clean(words[at])), at == 0 || !determiners.contains(clean(words[at - 1])), let host = host(in: words, after: at - 1), host.spoken {
                words.replaceSubrange(at ..< host.end, with: [host.name + host.tail])
            }
            at += 1
        }
        return words.joined(separator: " ")
    }

    private static func host(in words: [String], after at: Int) -> (name: String, end: Int, tail: String, spoken: Bool)? {
        var name = ""
        var end = at + 1
        var tail = ""
        var spoken = false
        while end < words.count {
            let label = words[end].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }.dropLast { $0 == "." }
            guard !label.isEmpty else { break }
            name += label.lowercased()
            tail = String(words[end].dropFirst(label.count))
            end += 1
            guard tail.isEmpty, end + 1 < words.count, clean(words[end]) == "dot" else { break }
            name += "."
            spoken = true
            end += 1
        }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, labels.allSatisfy({ !$0.isEmpty }), domains.contains(String(labels.last!)) else { return nil }
        return (name, end, tail, spoken)
    }

    /// Where the name before an "at" starts: the plain word beside it, and what's spoken as part of one before that.
    private static func local(in words: [String], before at: Int) -> Int? {
        var start = at
        while start > 0 {
            let word = words[start - 1]
            guard word.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else { break }
            let first = pieces(word).first
            let spelled = word.count == 1 || first.map { if case .number = $0 { true } else { false } } == true
            let joins = joiners.contains(word.lowercased()) || start < at && joiners.contains(words[start].lowercased())
            guard start == at || spelled || joins else { break }
            start -= 1
        }
        return start < at ? start : nil
    }

    private static func pieces(_ said: String, zeros: Set<String> = ["oh"]) -> [Piece] {
        var tokens: [Piece] = []
        var values: [Int?] = []
        for token in said.split(whereSeparator: \.isWhitespace) {
            let cleaned = joinedLetters(clean(String(token)))
            let parts = cleaned.split(separator: "-").map(String.init)
            for word in parts.count > 1 && parts.allSatisfy({ value(of: $0) != nil }) ? parts : [cleaned] where !word.isEmpty {
                let number = value(of: word)
                tokens.append(signs[word] != nil ? .symbol(word) : number.map { .number(String($0)) } ?? (word.allSatisfy(\.isNumber) ? .number(word) : .word(word)))
                values.append(number)
            }
        }
        var pieces: [Piece] = []
        var at = 0
        while at < tokens.count {
            if let tens = values[at], tens >= 20, tens % 10 == 0, at + 1 < tokens.count, let unit = values[at + 1], (1...9).contains(unit) {
                pieces.append(.number(String(tens + unit)))
                at += 2
            } else {
                pieces.append(tokens[at])
                at += 1
            }
        }
        for order in [Array(pieces.indices), pieces.indices.reversed()] {
            for at in order {
                guard case .word(let word) = pieces[at], zeros.contains(word) else { continue }
                let neighbours = [at - 1, at + 1].filter { pieces.indices.contains($0) }
                if neighbours.contains(where: { if case .number = pieces[$0] { true } else { false } }) { pieces[at] = .number("0") }
            }
        }
        return pieces
    }

    private static func value(of word: String) -> Int? {
        if let unit = units.firstIndex(of: word) { return unit }
        return tens.firstIndex(of: word).map { ($0 + 2) * 10 }
    }

    /// "peter" for "p-e-t-e-r", as the model writes letters you spell: a dash between two letters that each stand alone.
    private static func joinedLetters(_ token: String) -> String {
        let characters = Array(token)
        let alone = { (at: Int) in at < 0 || at >= characters.count || !characters[at].isLetter && !characters[at].isNumber }
        return String(characters.enumerated().filter { at, character in
            let spelled = character == "-" && at > 0 && at + 1 < characters.count && characters[at - 1].isLetter && characters[at + 1].isLetter
            return !(spelled && alone(at - 2) && alone(at + 2))
        }.map(\.element))
    }

    private static func clean(_ token: String) -> String {
        String(token.lowercased().drop { "\"'(".contains($0) }.reversed().drop { ".,;!?\")".contains($0) }.reversed())
    }
}
