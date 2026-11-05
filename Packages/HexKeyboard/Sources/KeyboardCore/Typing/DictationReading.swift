/// How a dictation is read for the field it goes into, which tells the keyboard what it holds: an email or web address
/// keyboard, or a content type of username, email or URL, reads what was said as an address; a number, phone or decimal
/// pad, or a telephone, one-time code, postal code or card number, as its digits, which the field formats itself; a
/// search field as an address when all of what was said is one, and otherwise, like every other field, as prose, which
/// is the speech model's own writing in the person's style. Dictating right after part of an address, with no space
/// between ("john@"), goes on with it. Readings take what the model wrote, not what the style and lists made of it.
enum DictationReading {
    /// What a dictation types as the field reads it, or nil when it's prose.
    static func typed(_ said: String, in traits: InputTraits, after before: String) -> String? {
        let reading: String? = switch (traits.content, traits.kind) {
        case (.emailAddress, _), (.url, _), (.username, _), (.other, .email), (.other, .url): SpokenAddress.read(said)
        case (.telephoneNumber, _), (.oneTimeCode, _), (.postalCode, _), (.creditCardNumber, _), (.other, .number), (.other, .decimal): SpokenAddress.digits(said)
        case (.other, .webSearch): SpokenAddress.domain(said)
        default: nil
        }
        return reading ?? (continuesAddress(before) ? SpokenAddress.read(said) : nil)
    }

    /// Whether the text ends in part of an address, which no space separates from the caret.
    private static func continuesAddress(_ before: String) -> Bool {
        let last = before.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace).last ?? ""
        return last.contains("@") || last.contains("://") || last.hasPrefix("www.")
    }
}
