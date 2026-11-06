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
}
