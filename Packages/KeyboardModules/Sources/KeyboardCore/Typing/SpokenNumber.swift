/// A decimal or a percentage the model wrote out in words, written as one: "Opus five point five" is "Opus 5.5",
/// "twenty seven point one" 27.1, "two point oh" 2.0 and "fifty percent" 50%, as it writes them when it doesn't itself.
/// Other numbers stay as written, and so does a point that's a word: "at one point five people left", "a five point
/// plan", "three points".
enum SpokenNumber {
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                                "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    /// Words before "one point" that make it a point you make.
    private static let determiners: Set<String> = ["at", "the", "a", "one", "that", "this", "my", "your", "our", "his", "her", "their",
                                                   "its", "each", "every", "any", "no", "some", "which", "what"]

    static func inline(_ text: String) -> String {
        guard text.contains("point") || text.contains("percent") else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var at = 0
        while at < words.count {
            if let number = number(in: words, at: at) {
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
