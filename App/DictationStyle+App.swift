import KeyboardCore
import KeyboardUI

extension DictationWriting {
    /// What Hex types for what the voice model wrote: as Settings › Voice writes it, then with your vocabulary's words,
    /// so a term keeps its own spelling. The keyboard sets its capitals.
    static func typed(_ heard: String) -> String {
        VoiceVocabulary.shared.vocabulary.corrected(SettingsStore.load().dictation.written(heard))
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

    var detail: String {
        switch self {
        case .asSaid: "Every word you say, um and uh too."
        case .light: "Leaves out um and uh."
        case .clean: "Also leaves out words said twice, like “the the”, and what you take back with “scratch that”."
        }
    }
}
