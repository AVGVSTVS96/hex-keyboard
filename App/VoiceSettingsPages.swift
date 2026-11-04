import KeyboardCore
import KeyboardUI
import SwiftUI

/// Which model writes what you say, with its download or why it couldn't get ready.
struct ModelSettings: View {
    private let voice = VoiceModel.shared

    var body: some View {
        Box(footer: "Everything you say is written down on this iPhone and never leaves it. What you dictate while a Parakeet gets ready is written once it’s ready, in the order you said it.") {
            ForEach([VoiceModel.Model.v3, .ultra, .apple], id: \.self) { choice in
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
                Button("Try Again") { voice.prepare() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.top, 8)
        case .ready:
            EmptyView()
        }
    }
}

/// The words and punctuation iikb types for what you say: a preview of the same words as picked, then each style and
/// each level of editing shown by how it types them with everything else as picked.
struct WritingSettings: View {
    private static let said = "So, let's send it to Sam tonight."
    private static let rambled = "Um, I think the the plan works."
    private static let preview = "Um, so I think the the plan works, let's send it to Sam tonight."
    private let model = SettingsModel.shared

    private func typed(_ said: String, _ change: (inout DictationWriting) -> Void = { _ in }) -> String {
        var writing = model.settings.dictation
        change(&writing)
        return writing.typed(said, lexicon: .english)
    }

    private func quoted(_ said: String, _ change: (inout DictationWriting) -> Void) -> String {
        "“" + typed(said, change) + "”"
    }

    var body: some View {
        WritingPreview(said: Self.preview, typed: typed(Self.preview))
        Box(header: "Style", footer: "A style sets the punctuation. Capitals follow Auto-Capitalization in Keyboard › Typing; very casual has none.") {
            ForEach(DictationStyle.allCases, id: \.self) { style in
                ChoiceRow(title: style.title, detail: quoted(Self.said) { $0.style = style }, picked: model.settings.dictationStyle == style) {
                    withAnimation(.snappy(duration: 0.25)) { model.update { $0.dictationStyle = style } }
                }
            }
        }
        Box(header: "Editing", footer: "Clean also takes back what you cancel with “scratch that”. Transcripts keep what the model wrote.") {
            ForEach(DictationEditing.allCases, id: \.self) { editing in
                ChoiceRow(title: editing.title, detail: quoted(Self.rambled) { $0.editing = editing }, picked: model.settings.dictationEditing == editing) {
                    withAnimation(.snappy(duration: 0.25)) { model.update { $0.dictationEditing = editing } }
                }
            }
        }
        Box {
            ToggleRow(title: "Lists", detail: "“One, eggs, two, milk” is typed as a numbered list. First, second works too.", isOn: model.binding(\.dictationLists))
        }
    }
}

/// What you say over what iikb types for it, as picked, so a change shows at once.
private struct WritingPreview: View {
    let said: String
    let typed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            line("You say", said, primary: false)
            Rectangle().fill(Color.hexDivider).frame(height: 1)
            line("iikb types", typed, primary: true)
                .contentTransition(.opacity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ text: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.hexSecondary)
            Text(text)
                .font(primary ? .title3.weight(.medium) : .body)
                .foregroundStyle(primary ? Color.primary : Color.hexSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How long the mic stays on after a dictation.
struct MicSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(footer: "After you dictate, iikb keeps the mic on this long, so the mic beside the suggestions starts and stops without leaving your app. Hold it to turn the mic off.") {
            ForEach(Dictation.micChoices, id: \.self) { seconds in
                ChoiceRow(title: Dictation.title(keepingMicOn: seconds), picked: model.keepMicOn == seconds) { model.keepMicOn(seconds) }
            }
        }
    }
}
