import KeyboardCore
import KeyboardUI
import SwiftUI

/// Which model writes what you say, with its download or why it couldn't get ready.
struct ModelSettings: View {
    private let voice = VoiceModel.shared

    var body: some View {
        Box(footer: "What you say is written on this iPhone and never leaves it. A dictation made while a Parakeet gets ready waits for it.") {
            ForEach(VoiceModel.Model.allCases, id: \.self) { choice in
                ChoiceRow(title: choice.title, detail: choice.detail, picked: choice == voice.model) {
                    voice.pick(choice)
                } extra: {
                    if choice == voice.model, voice.state != .ready { progress }
                }
            }
        }
    }

    @ViewBuilder private var progress: some View {
        switch voice.state {
        case .downloading(let done):
            ProgressView(value: done) {
                Text("Downloading, \(done.formatted(.percent.precision(.fractionLength(0))))")
            }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
            .padding(.top, 8)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Getting ready")
            }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
            .padding(.top, 8)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn’t get it ready: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Try Again") { voice.retry() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.top, 8)
        case .ready:
            EmptyView()
        }
    }
}

/// The words and punctuation Hex types for what you say.
struct WritingSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(header: "Style", footer: "A style sets capitals and punctuation, as Wispr Flow’s do. Fields that want no capitals, like web addresses, get none.") {
            ForEach(DictationStyle.allCases, id: \.self) { style in
                ChoiceRow(title: style.title, detail: style.detail, picked: model.settings.dictationStyle == style) { model.update { $0.dictationStyle = style } }
            }
        }
        Box(header: "Editing", footer: "Transcripts keep what the model wrote.") {
            ForEach(DictationEditing.allCases, id: \.self) { editing in
                ChoiceRow(title: editing.title, detail: editing.detail, picked: model.settings.dictationEditing == editing) { model.update { $0.dictationEditing = editing } }
            }
            ToggleRow(title: "Lists", detail: "“One, eggs, two, milk” is typed as a numbered list. First, second works too.", isOn: model.binding(\.dictationLists))
        }
    }
}

/// How long the mic stays on after a dictation.
struct MicSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(footer: "After you dictate, Hex keeps the mic on this long, so the mic beside the suggestions starts and stops without leaving your app. Hold it to turn the mic off.") {
            ForEach(Dictation.micChoices, id: \.self) { seconds in
                ChoiceRow(title: Dictation.title(keepingMicOn: seconds), picked: model.keepMicOn == seconds) { model.keepMicOn(seconds) }
            }
        }
    }
}
