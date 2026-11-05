import Testing
@testable import KeyboardCore

struct DictationReadingTests {
    private func dictate(_ heard: String, plain: String? = nil, into text: String = "", kind: InputKind = .text, content: InputContent = .other) -> String {
        var engine = TypingEngine(traits: InputTraits(kind: kind, content: content))
        engine.corrector = Corrector(source: testLexicon)
        let document = TestDocument(text)
        engine.handle(.dictated(heard, plain: plain), in: document)
        return document.text
    }

    @Test func anEmailFieldReadsSpokenFormsAsOneAddress() {
        #expect(dictate("Theo to a one at fastmail.com", kind: .email) == "theotoa1@fastmail.com")
        #expect(dictate("John dot Smith at Gmail dot com.", kind: .email) == "john.smith@gmail.com")
        #expect(dictate("Jane underscore Doe 99 at yahoo.com", kind: .email) == "jane_doe99@yahoo.com")
        #expect(dictate("j o h n at example dot org", content: .emailAddress) == "john@example.org")
        #expect(dictate("Ann, twenty one at example dot com.", kind: .email) == "ann21@example.com")
        #expect(dictate("pat at at dot com", kind: .email) == "pat@at.com")
        #expect(dictate("P-E-T-E-R.q at fastmail.com", kind: .email) == "peter.q@fastmail.com")
    }

    @Test func aURLFieldReadsAWebAddress() {
        #expect(dictate("w w w dot example dot com slash pricing", kind: .url) == "www.example.com/pricing")
        #expect(dictate("HTTP colon slash slash example dot com", content: .url) == "http://example.com")
        #expect(dictate("our dash team dot io", content: .username) == "our-team.io")
    }

    @Test func aNumberFieldTypesTheDigitsSaid() {
        #expect(dictate("Five five five, one two three four.", kind: .number) == "5551234")
        #expect(dictate("Oh seven, oh nine.", content: .oneTimeCode) == "0709")
        #expect(dictate("O seven two three.", content: .oneTimeCode) == "0723")
        #expect(dictate("Nine four one oh five", content: .postalCode) == "94105")
        #expect(dictate("Twenty twenty four", kind: .decimal) == "2024")
        #expect(dictate("(555) 123-4567.", kind: .number) == "5551234567")
        #expect(dictate("Plus one four one five, five five five, zero one nine nine.", content: .telephoneNumber) == "+14155550199")
        #expect(dictate("+1 415-555-0199.", kind: .number) == "+14155550199")
        #expect(dictate("Three point five", kind: .decimal) == "3.5")
        #expect(dictate("It's 12.75.", kind: .decimal) == "12.75")
        #expect(dictate("Nine four one oh five.", kind: .number) == "94105")
    }

    @Test func aNumberFieldWithNoDigitsTypesProse() {
        #expect(dictate("Hello there.", kind: .number) == "Hello there.")
    }

    @Test func aSearchFieldReadsAnAddressOnlyWhenAllOfItIsOne() {
        #expect(dictate("example dot com", kind: .webSearch) == "example.com")
        #expect(dictate("Docs dot python dot org slash tutorial", kind: .webSearch) == "docs.python.org/tutorial")
        #expect(dictate("How to reach example dot com.", kind: .webSearch) == "How to reach example dot com.")
        #expect(dictate("Pizza near me.", kind: .webSearch) == "Pizza near me.")
        #expect(dictate("Python 3.12 release notes", kind: .webSearch) == "Python 3.12 release notes")
    }

    @Test func aDictationRightAfterPartOfAnAddressGoesOnWithIt() {
        #expect(dictate("Gmail dot com.", into: "john@") == "john@gmail.com")
        #expect(dictate("Gmail dot com.", into: "john ") == "john Gmail dot com.")
    }

    @Test func anAddressIsReadFromWhatTheModelWroteNotTheStyledText() {
        #expect(dictate("1. five five five\n2. one two three", plain: "Five five five, one two three", kind: .number) == "555123")
        #expect(dictate("Theo at Example.", plain: "theo at example dot com", kind: .email) == "theo@example.com")
    }

    @Test func anEmailSpokenInASentenceIsWrittenAsOne() {
        #expect(dictate("Email me at john at gmail dot com.") == "Email me at john@gmail.com.")
        #expect(dictate("Send it to Jane dot Doe at example dot org, please.") == "Send it to jane.doe@example.org, please.")
        #expect(dictate("Send a message to j o h n at example dot com.") == "Send a message to john@example.com.")
        #expect(dictate("Write to Milo99 at iCloud.com tomorrow.") == "Write to milo99@icloud.com tomorrow.")
        #expect(dictate("Reach me at ruby.stone at acme.io.") == "Reach me at ruby.stone@acme.io.")
    }

    @Test func proseWithoutAnAddressIsUntouched() {
        for said in ["Meet me at the park dot com is down.", "I was at home. Then, I left.", "We shop at example.com every week.", "Her address is Zara at proton.me."] {
            #expect(dictate(said) == said)
        }
    }
}
