import KeyboardCore
import KeyboardUI

extension DictationStyle {
    /// What Hex types for what the voice model wrote: in the style picked in Settings, then with your vocabulary's
    /// words, so a term keeps its own capitals.
    static func typed(_ heard: String) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(SettingsStore.dictationStyle.written(heard, lexicon: .english))
    }

    /// Wispr Flow's names, each written in its style.
    var title: String {
        switch self {
        case .asSaid: "As Said"
        case .formal: "Formal."
        case .casual: "Casual"
        case .veryCasual: "very casual"
        }
    }

    var example: String {
        written("Um, so I think it's done. Cheryl liked it.", lexicon: .english)
    }
}
