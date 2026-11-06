/// A decimal, a percentage or a run of digits the model wrote out in words, written as one: "Opus five point five" is
/// "Opus 5.5", "twenty seven point one" 27.1, "two point oh" 2.0, "fifty percent" 50% and "four one five five five five
/// zero one nine nine" 415-555-0199, as it writes them when it doesn't itself, and a phone number it wrote with
/// spaces ("415 555 0199") or together ("4155550199") with dashes, as it mostly writes one; and a time or an amount in
/// dollars as Bassim types one ("3:30pm", "9am", "$25", "$5.50"). Other numbers stay as written, and so do
/// a point that's a word ("at one point five people left", "a five point plan", "three points") and counting ("one two
/// three four", "five, four, three, two, one", "one two, one two").
enum SpokenNumber {
    /// Words that ask for a code or number said after them, so four digits are one.
    private static let cues: Set<String> = ["code", "pin", "number", "passcode", "password", "extension", "zip", "id", "digits", "otp"]
    /// Words before "one point" that make it a point you make.
    private static let determiners = Spoken.determiners.union(["at", "one", "each", "every", "any", "no", "some", "which", "what"])

    static func inline(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var at = 0
        while at < words.count {
            if let number = time(in: words, at: at) ?? money(in: words, at: at) ?? number(in: words, at: at) ?? digits(in: words, at: at) ?? phone(in: words, at: at) {
                words.replaceSubrange(at ..< number.end, with: [number.written])
            }
            at += 1
        }
        return words.joined(separator: " ")
    }

    /// A time of day said with its "am" or "pm", written as Bassim types one: "three thirty PM" and "3 30 p.m." are
    /// "3:30pm", "nine A.M." "9am", "ten fifteen AM" "10:15am". Without one ("at three thirty") it stays.
    private static func time(in words: [String], at: Int) -> (written: String, end: Int)? {
        let first = words[at].lowercased()
        var hour: Int?, minutes: String?, end = at + 1
        if let match = first.wholeMatch(of: /(\d{1,2})(?:[:.](\d\d))?/) {
            hour = Int(match.1)
            minutes = match.2.map(String.init)
        } else {
            hour = Spoken.value(of: first)
        }
        guard let hour, (1...12).contains(hour), end < words.count else { return nil }
        if minutes == nil, let (said, after) = self.minutes(in: words, at: end) {
            minutes = said
            end = after
        }
        guard end < words.count, let (meridiem, tail) = meridiem(words[end], next: end + 1 < words.count ? words[end + 1] : nil) else { return nil }
        return ("\(hour)" + (minutes.map { ":" + $0 } ?? "") + meridiem + tail, end + 1)
    }

    /// The minutes said after an hour, as two digits: "30", "fifteen", "forty five", "oh five".
    private static func minutes(in words: [String], at: Int) -> (String, Int)? {
        let (word, tail) = split(words[at])
        guard tail.isEmpty else { return nil }
        if word.count == 2, let value = Int(word), value < 60 { return (word, at + 1) }
        if word == "oh", at + 1 < words.count, case let (next, "") = split(words[at + 1]), let digit = Spoken.digit(next), digit > 0 {
            return ("0\(digit)", at + 2)
        }
        guard let (value, end) = Spoken.cardinal(run(words, from: at), at: 0),
              (10...59).contains(value) else { return nil }
        return (String(value), at + end)
    }

    /// "am" or "pm" as said ("AM", "p.m.", "pm,") and what follows it: a period that ends the sentence, before a
    /// capital, or any other mark. Lowercase "am" before "I" is the verb.
    private static func meridiem(_ token: String, next: String?) -> (String, String)? {
        guard let match = token.prefixMatch(of: /(?i)([ap])(\.?)m(\.?)/) else { return nil }
        var tail = String(token[match.range.upperBound...])
        guard tail.allSatisfy({ !$0.isLetter && !$0.isNumber }) else { return nil }
        if token.hasPrefix("am"), next.map({ split($0).word }) == "i" { return nil }
        if match.3 == ".", tail.isEmpty, next?.first?.isUppercase == true { tail = "." }
        if match.2.isEmpty, match.3 == "." { tail = "." + tail }
        return (match.1.lowercased() + "m", tail)
    }

    /// An amount said in dollars, written with its sign: "twenty-five dollars" is "$25", "two hundred dollars" "$200",
    /// "five dollars and fifty cents" "$5.50", though not a guess ("two or three dollars").
    private static func money(in words: [String], at: Int) -> (written: String, end: Int)? {
        let said = run(words, from: at)
        guard at == 0 || split(words[at - 1]).word != "or", let (dollars, used) = Spoken.cardinal(said, at: 0), used < said.count,
              said[used] == "dollars" || said[used] == "dollar" && dollars == 1 else { return nil }
        var end = at + used + 1, cents = ""
        if split(words[end - 1]).tail.isEmpty, end < words.count {
            let from = split(words[end]).word == "and" ? end + 1 : end
            let more = run(words, from: from)
            if let (value, used) = Spoken.cardinal(more, at: 0), (1...99).contains(value), used < more.count,
               more[used] == "cents" || more[used] == "cent" && value == 1 {
                cents = "." + (value < 10 ? "0" : "") + String(value)
                end = from + used + 1
            }
        }
        return ("$" + Spoken.grouped(dollars) + cents + split(words[end - 1]).tail, end)
    }

    /// The words from `at` lowercase without their punctuation, up to and including the first with a mark after it,
    /// which ends what's said.
    private static func run(_ words: [String], from at: Int) -> [String] {
        guard at < words.count else { return [] }
        let end = words[at...].firstIndex { !split($0).tail.isEmpty } ?? words.count - 1
        return words[at...end].map { split($0).word }
    }

    /// The decimal or percentage starting at `at`, written, and where its words end.
    private static func number(in words: [String], at: Int) -> (written: String, end: Int)? {
        guard var (written, end) = whole(in: words, at: at), end < words.count else { return nil }
        if words[at].lowercased() == "one", at > 0, determiners.contains(split(words[at - 1]).word) { return nil }
        if words[end].lowercased() == "point" {
            var fraction = "", tail = ""
            end += 1
            while end < words.count, tail.isEmpty, let digit = digit(split(words[end]).word) {
                fraction += digit
                tail = split(words[end]).tail
                end += 1
            }
            guard !fraction.isEmpty else { return nil }
            written += "." + fraction
            guard tail.isEmpty, end < words.count, split(words[end]).word == "percent" else { return (written + tail, end) }
        }
        guard split(words[end]).word == "percent" else { return nil }
        return (written + "%" + split(words[end]).tail, end + 1)
    }

    /// Digits said one by one from `at`, as a phone number, code or PIN is: five or more, or four with an "oh" or after
    /// a word that asks for them ("the code is"), grouped as said (each group between commas three digits or more) or
    /// else as a phone number's are. Never counting: a group that counts up or down by one, a run whose every step is
    /// the same ("two four six eight"), a group said again, or a pair said over and over.
    private static func digits(in words: [String], at: Int) -> (written: String, end: Int)? {
        if at > 0, spoken(split(words[at - 1]).word, first: true) != nil { return nil }
        var groups = [""], end = at, tail = "", said = false
        while end < words.count, case let (word, rest) = split(words[end]),
              let digit = spoken(word, first: end == at, next: end + 1 < words.count && rest.isEmpty ? split(words[end + 1]).word : nil) {
            said = said || word == "oh"
            groups[groups.count - 1] += digit
            end += 1
            guard !rest.isEmpty else { continue }
            if rest == ",", end < words.count, spoken(split(words[end]).word, first: false) != nil {
                groups.append("")
            } else {
                tail = rest
                break
            }
        }
        let all = groups.joined()
        let steps = { (digits: String) in Set(zip(digits, digits.dropFirst()).map { $1.wholeNumberValue! - $0.wholeNumberValue! }) }
        let asked = words[max(0, at - 3) ..< at].contains { cues.contains(split($0).word) }
        guard all.count >= 5 || all.count == 4 && (said || asked), groups.count == 1 || groups.allSatisfy({ $0.count >= 3 }),
              steps(all).count > 1, !groups.contains(where: { $0.count >= 3 && [[1], [-1]].contains(steps($0)) }),
              Set(groups).count == groups.count, all.dropFirst(2) != all.dropLast(2) else { return nil }
        let split = { (sizes: [Int]) in sizes.reduce(into: (parts: [String](), rest: Substring(all))) { $0.parts.append(String($0.rest.prefix($1))); $0.rest = $0.rest.dropFirst($1) }.parts.joined(separator: "-") }
        let written = groups.count > 1 ? groups.joined(separator: "-")
            : all.count == 10 ? split([3, 3, 4]) : all.count == 11 && all.first == "1" ? split([1, 3, 3, 4]) : all
        return (written + tail, end)
    }

    /// A phone number written in groups of digits with spaces, 3-3-4 after an optional 1 or +1.
    private static func phone(in words: [String], at: Int) -> (written: String, end: Int)? {
        if case let (word, tail) = split(words[at]), word.allSatisfy(\.isNumber), let number = together(word) { return (number + tail, at + 1) }
        let sizes = words[at] == "1" || words[at] == "+1" ? [words[at].count, 3, 3, 4] : [3, 3, 4]
        guard at + sizes.count <= words.count else { return nil }
        let groups = (0 ..< sizes.count).map { words[at + $0] }
        let last = groups.last!.prefix { $0.isNumber }
        let digits = groups.dropLast() + [String(last)]
        guard zip(digits, sizes).allSatisfy({ $0.count == $1 && $0.allSatisfy { $0.isNumber || $0 == "+" } }),
              at + sizes.count == words.count || !(words[at + sizes.count].first?.isNumber ?? false),
              at == 0 || !(words[at - 1].last?.isNumber ?? false) else { return nil }
        return (digits.joined(separator: "-") + groups.last!.dropFirst(last.count), at + sizes.count)
    }

    /// Ten digits written together as a phone number is, 3-3-4, or eleven after a 1: an area code and an exchange each
    /// start with 2 to 9, so a timestamp or an order number isn't one.
    private static func together(_ digits: String) -> String? {
        let digits = Array(digits)
        let local = digits.count == 11 && digits[0] == "1" ? Array(digits.dropFirst()) : digits
        guard local.count == 10, local[0] >= "2", local[3] >= "2" else { return nil }
        return (digits.count == 11 ? "1-" : "") + [local[0..<3], local[3..<6], local[6...]].map { String($0) }.joined(separator: "-")
    }

    /// One digit said, with "oh" for 0 inside a run, before another digit.
    private static func spoken(_ word: String, first: Bool, next: String? = nil) -> String? {
        if !first, word == "oh", let next, next == "oh" || Spoken.digit(next) != nil { return "0" }
        return Spoken.digit(word).map(String.init)
    }

    /// The whole number starting at `at` with nothing after it: digits, or a number word under a hundred ("twenty
    /// seven", "twenty-seven").
    private static func whole(in words: [String], at: Int) -> (digits: String, end: Int)? {
        let (word, tail) = split(words[at])
        guard !word.isEmpty, tail.isEmpty else { return nil }
        if word.allSatisfy(\.isNumber) { return (word, at + 1) }
        let parts = word.split(separator: "-").map(String.init)
        if parts.count == 2, let tens = Spoken.value(of: parts[0]), let unit = Spoken.value(of: parts[1]), let number = Spoken.joined(tens, unit) {
            return (String(number), at + 1)
        }
        guard let value = Spoken.value(of: word) else { return nil }
        if at + 1 < words.count, case let (next, "") = split(words[at + 1]), let unit = Spoken.value(of: next),
           let number = Spoken.joined(value, unit) {
            return (String(number), at + 2)
        }
        return (String(value), at + 1)
    }

    /// One digit, said or written, after a point.
    private static func digit(_ word: String) -> String? {
        if !word.isEmpty, word.allSatisfy(\.isNumber) { return word }
        if word == "oh" { return "0" }
        return Spoken.digit(word).map(String.init)
    }

    /// A word lowercased, apart from the punctuation after it.
    private static func split(_ token: String) -> (word: String, tail: String) {
        let word = token.prefix { $0.isLetter || $0.isNumber || $0 == "-" }
        return (word.lowercased(), String(token.dropFirst(word.count)))
    }
}
