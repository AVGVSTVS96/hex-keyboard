/// A decimal, a percentage or a run of digits the model wrote out in words, written as one: "Opus five point five" is
/// "Opus 5.5", "twenty seven point one" 27.1, "two point oh" 2.0, "fifty percent" 50% and "four one five five five five
/// zero one nine nine" 415-555-0199, as it writes them when it doesn't itself, and a phone number it wrote with
/// spaces ("415 555 0199") with dashes, as it mostly writes one. Other numbers stay as written, and so do
/// a point that's a word ("at one point five people left", "a five point plan", "three points") and counting ("one two
/// three four", "five, four, three, two, one", "one two, one two").
enum SpokenNumber {
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                                "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    /// Words before "one point" that make it a point you make.
    private static let determiners: Set<String> = ["at", "the", "a", "one", "that", "this", "my", "your", "our", "his", "her", "their",
                                                   "its", "each", "every", "any", "no", "some", "which", "what"]

    static func inline(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var at = 0
        while at < words.count {
            if let number = number(in: words, at: at) ?? digits(in: words, at: at) ?? phone(in: words, at: at) {
                words.replaceSubrange(at ..< number.end, with: [number.written])
            }
            at += 1
        }
        return words.joined(separator: " ")
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

    /// Four or more digits said one by one from `at`, as a phone number, code or PIN is, grouped as said (each group
    /// between commas three digits or more) or else as a phone number's are; never a count up or down or a pair said
    /// over and over.
    private static func digits(in words: [String], at: Int) -> (written: String, end: Int)? {
        if at > 0, case let (before, "") = split(words[at - 1]), spoken(before, first: true) != nil { return nil }
        var groups = [""], end = at, tail = ""
        while end < words.count, case let (word, rest) = split(words[end]), let digit = spoken(word, first: end == at) {
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
        let values = all.compactMap(\.wholeNumberValue)
        let steps = Set(zip(values, values.dropFirst()).map { $1 - $0 })
        guard all.count >= 4, groups.count == 1 || groups.allSatisfy({ $0.count >= 3 }), steps != [1], steps != [-1],
              all.dropFirst(2) != all.dropLast(2) else { return nil }
        let split = { (sizes: [Int]) in sizes.reduce(into: (parts: [String](), rest: Substring(all))) { $0.parts.append(String($0.rest.prefix($1))); $0.rest = $0.rest.dropFirst($1) }.parts.joined(separator: "-") }
        let written = groups.count > 1 ? groups.joined(separator: "-")
            : all.count == 7 ? split([3, 4]) : all.count == 10 ? split([3, 3, 4]) : all.count == 11 && all.first == "1" ? split([1, 3, 3, 4]) : all
        return (written + tail, end)
    }

    /// A phone number written in groups of digits with spaces, 3-3-4 after an optional 1 or +1.
    private static func phone(in words: [String], at: Int) -> (written: String, end: Int)? {
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

    /// One digit said, with "oh" for 0 inside a run.
    private static func spoken(_ word: String, first: Bool) -> String? {
        if !first, word == "oh" { return "0" }
        return units.firstIndex(of: word).flatMap { $0 < 10 ? String($0) : nil }
    }

    /// The whole number starting at `at` with nothing after it: digits, or a number word under a hundred ("twenty
    /// seven", "twenty-seven").
    private static func whole(in words: [String], at: Int) -> (digits: String, end: Int)? {
        let (word, tail) = split(words[at])
        guard !word.isEmpty, tail.isEmpty else { return nil }
        if word.allSatisfy(\.isNumber) { return (word, at + 1) }
        let parts = word.split(separator: "-").map(String.init)
        if parts.count == 2, let ten = tens.firstIndex(of: parts[0]), let unit = units.firstIndex(of: parts[1]), (1...9).contains(unit) {
            return (String((ten + 2) * 10 + unit), at + 1)
        }
        if let unit = units.firstIndex(of: word) { return (String(unit), at + 1) }
        guard let ten = tens.firstIndex(of: word) else { return nil }
        if at + 1 < words.count, case let (next, "") = split(words[at + 1]), let unit = units.firstIndex(of: next), (1...9).contains(unit) {
            return (String((ten + 2) * 10 + unit), at + 2)
        }
        return (String((ten + 2) * 10), at + 1)
    }

    /// One digit, said or written, after a point.
    private static func digit(_ word: String) -> String? {
        if !word.isEmpty, word.allSatisfy(\.isNumber) { return word }
        if word == "oh" { return "0" }
        return units.firstIndex(of: word).flatMap { $0 < 10 ? String($0) : nil }
    }

    /// A word lowercased, apart from the punctuation after it.
    private static func split(_ token: String) -> (word: String, tail: String) {
        let word = token.prefix { $0.isLetter || $0.isNumber || $0 == "-" }
        return (word.lowercased(), String(token.dropFirst(word.count)))
    }
}
