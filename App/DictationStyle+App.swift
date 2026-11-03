import KeyboardCore
import KeyboardUI

extension DictationStyle {
    /// What Hex types for what the voice model wrote: in the style picked in Settings, with um and uh or without, then
    /// with your vocabulary's words, so a term keeps its own spelling. The keyboard sets its capitals.
    static func typed(_ heard: String) -> String {
        let written = SettingsStore.dictationStyle.written(heard, keepingFillers: SettingsStore.keepsUmAndUh)
        return VoiceVocabulary.shared.vocabulary.corrected(written)
    }

    /// Wispr Flow's names, each written in its style.
    var title: String {
        switch self {
        case .formal: "Formal."
        case .casual: "Casual"
        }
    }

    var detail: String {
        switch self {
        case .formal: "Ends with a period."
        case .casual: "Leaves the last period off"
        }
    }
}
