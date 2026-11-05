import KeyboardCore
import KeyboardEnglish
import KeyboardStore

extension DictationWriting {
    /// What iikb types for what the voice model wrote: as Settings › Voice writes it, then with your vocabulary's words
    /// and the made-up words that sound like them, so a term keeps its own spelling. The keyboard sets its capitals.
    static func typed(_ heard: String) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(SettingsStore.load().dictation.written(heard), lexicon: .english)
    }

    /// What the voice model wrote, with your vocabulary's words and nothing of the style or lists.
    static func plain(_ heard: String) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(heard, lexicon: .english)
    }
}

extension DictationStyle {
    /// Wispr Flow's names, each written in its style.
    var title: String {
        switch self {
        case .formal: "Formal."
        case .casual: "Casual"
        case .veryCasual: "very casual"
        case .excited: "Excited!"
        }
    }
}

extension DictationEditing {
    var title: String {
        switch self {
        case .asSaid: "As Said"
        case .light: "Light"
        case .clean: "Clean"
        }
    }
}

extension DictationLists {
    var title: String {
        switch self {
        case .numbered: "Numbered"
        case .bulleted: "Bulleted"
        case .off: "Off"
        }
    }
}
