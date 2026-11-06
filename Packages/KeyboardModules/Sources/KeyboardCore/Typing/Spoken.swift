/// The words a number or an address is said in, which `SpokenNumber` and `SpokenAddress` read alike.
enum Spoken {
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                                "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// Words that point at what follows, so it's a thing named and not a number or address said: "the dot com bubble",
    /// "my dot files", "that one point".
    static let determiners: Set<String> = ["the", "a", "an", "this", "that", "my", "your", "our", "his", "her", "their", "its"]

    /// What a number word under a hundred is worth: "seven" 7, "twenty" 20.
    static func value(of word: some StringProtocol) -> Int? {
        if let unit = units.firstIndex(where: { $0 == word }) { return unit }
        return tens.firstIndex(where: { $0 == word }).map { ($0 + 2) * 10 }
    }

    /// The digit a word says, "zero" to "nine".
    static func digit(_ word: some StringProtocol) -> Int? {
        value(of: word).flatMap { $0 < 10 ? $0 : nil }
    }

    /// A tens word and a unit after it as one number: 20 and 7 are 27.
    static func joined(_ tens: Int, _ unit: Int) -> Int? {
        tens >= 20 && tens % 10 == 0 && (1...9).contains(unit) ? tens + unit : nil
    }

    /// The number said from `at` in `words`, each lowercase without its punctuation, and where it ends: digits ("25",
    /// "1,200") or number words with hundreds, thousands and millions ("two hundred and fifty", "three thousand five
    /// hundred", "twenty-five"). A word that can't go on the number ends it, so "one two" is 1.
    static func cardinal(_ words: [String], at: Int) -> (value: Int, end: Int)? {
        guard at < words.count else { return nil }
        if let value = Int(words[at].filter { $0 != "," }), words[at].first?.isNumber == true, words[at].allSatisfy({ $0.isNumber || $0 == "," }) {
            return (value, at + 1)
        }
        var total = 0, group = 0, end = at, said = false
        while end < words.count {
            let word = words[end]
            let parts = word.split(separator: "-")
            let value = parts.count == 2 ? value(of: parts[0]).flatMap { tens in value(of: parts[1]).flatMap { joined(tens, $0) } } : value(of: word)
            if let value, !said || total + group > 0, group % 100 == 0 || joined(group % 100, value) != nil {
                group += value
            } else if word == "hundred", said, (1...99).contains(group) {
                group *= 100
            } else if let scale = ["thousand": 1_000, "million": 1_000_000][word], said, group > 0, total == 0 || total > group * scale {
                total += group * scale
                group = 0
            } else if word == "and", said, group % 100 == 0, end + 1 < words.count, self.value(of: words[end + 1]) != nil {
                end += 1
                continue
            } else {
                break
            }
            said = true
            end += 1
        }
        return said ? (total + group, end) : nil
    }

    /// `value` with a comma between each three digits, as an amount is written: 3500 is "3,500".
    static func grouped(_ value: Int) -> String {
        var digits = String(value), out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits.removeLast(3)
        }
        return digits + out
    }
}
