import KeyboardStore
import KeyboardCore
import KeyboardEnglish
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
            .foregroundStyle(Color.appSecondary)
            .padding(.top, 8)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Getting ready")
            }
            .font(.footnote)
            .foregroundStyle(Color.appSecondary)
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

/// The words and punctuation iikb types for what you say: a preview of the same words as picked, then each style, each
/// level of editing and each way of writing a list shown by how it types them with everything else as picked.
struct WritingSettings: View {
    private static let said = "Hey, are you free tonight. Let's grab dinner, and then see the show."
    private static let rambled = "Um, I think the the plan is, like, two, I mean three."
    private static let listed = "Buy one, eggs, two, milk, three, bread."
    private static let preview = "Um, so are you free tonight. Let's grab dinner at the the place on Main, and then see the show at two, I mean three."
    private let model = SettingsModel.shared

    private func typed(_ said: String, _ change: (inout DictationWriting) -> Void = { _ in }) -> String {
        var writing = model.settings.dictation(in: nil)
        change(&writing)
        return writing.typed(said, lexicon: .english)
    }

    private func quoted(_ said: String, _ change: (inout DictationWriting) -> Void) -> String {
        "“" + typed(said, change) + "”"
    }

    /// The apps you've dictated into, most dictated first, then any other with a style of its own.
    private var apps: [String] {
        var counts: [String: Int] = [:]
        for case let app? in Transcripts.shared.all.map(\.app) where app != Bundle.main.bundleIdentifier { counts[app, default: 0] += 1 }
        for app in model.settings.appDictationStyles.keys where counts[app] == nil { counts[app] = 0 }
        return counts.sorted { ($0.value, AppName.of($1.key)) > ($1.value, AppName.of($0.key)) }.map(\.key)
    }

    private func style(in app: String) -> Binding<DictationStyle?> {
        Binding { model.settings.appDictationStyles[app] } set: { style in
            withAnimation(.snappy(duration: 0.25)) { model.update { $0.appDictationStyles[app] = style } }
        }
    }

    var body: some View {
        WritingPreview(said: Self.preview, typed: typed(Self.preview))
        Box(header: "Style", footer: "A style sets all the punctuation. Formal keeps every mark; Casual drops the last period and the comma after “so” or “hey”; very casual also drops capitals and the comma before “and” or “but”; Excited! ends short sentences with “!”. Every style asks a question with “?”. Capitals follow Auto-Capitalization in Keyboard › Typing.") {
            ForEach(DictationStyle.allCases, id: \.self) { style in
                ChoiceRow(title: style.title, detail: quoted(Self.said) { $0.style = style }, picked: model.settings.dictationStyle == style) {
                    withAnimation(.snappy(duration: 0.25)) { model.update { $0.dictationStyle = style } }
                }
            }
        }
        if !apps.isEmpty {
            Box(header: "Style in Each App", footer: "An app on Default writes in the style above. Each app you dictate into shows here.") {
                ForEach(apps, id: \.self) { app in
                    MenuRow(title: AppName.of(app), selection: style(in: app), choices: [nil] + DictationStyle.allCases) { $0?.title ?? "Default" }
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
        Box(header: "Lists", footer: "A list you say with one, two or first, second is written on lines of its own.") {
            ForEach(DictationLists.allCases, id: \.self) { lists in
                ChoiceRow(title: lists.title, detail: typed(Self.listed) { $0.lists = lists }, picked: model.settings.dictationLists == lists) {
                    withAnimation(.snappy(duration: 0.25)) { model.update { $0.dictationLists = lists } }
                }
            }
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
            Rectangle().fill(Color.appDivider).frame(height: 1)
            line("iikb types", typed, primary: true)
                .contentTransition(.opacity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ text: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.appSecondary)
            Text(text)
                .font(primary ? .title3.weight(.medium) : .body)
                .foregroundStyle(primary ? Color.primary : Color.appSecondary)
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

/// Which microphone iikb dictates with when there are several.
struct MicrophoneSettings: View {
    private let choices = MicrophoneChoices.shared
    @AppStorage("compareMicrophones") private var comparing = true

    var body: some View {
        Box(footer: "Automatic hears from the iPhone, or a wired headset when one is plugged in, never from Bluetooth, so music on AirPods and speakers keeps its full quality while you dictate. A Bluetooth microphone puts its device on a call, at call quality, while the mic is on. A pick is used whenever it’s connected; when it isn’t, the iPhone’s hears.") {
            ChoiceRow(title: "Automatic", picked: choices.picked == nil) { choices.pick(nil) }
            ForEach(choices.all, id: \.uid) { microphone in
                ChoiceRow(title: microphone.title, detail: detail(microphone), picked: choices.isPicked(microphone)) { choices.pick(microphone) }
            }
        }
        Box(footer: "Each dictation is heard one of two ways, at random: through Apple’s voice processing, as a call is, or as the front microphones hear it, aimed at you, with nothing taken away. Each transcript keeps which, so what you edit shows which writes your words best. Only on an iPhone that can aim its microphones, with Automatic picked, while its own microphone hears and nothing plays on its speaker.") {
            ToggleRow(title: "Compare Microphones", isOn: $comparing)
        }
        .onAppear { choices.reload() }
    }

    private func detail(_ microphone: PickedMicrophone) -> String? {
        switch (microphone.kind, choices.isAway(microphone)) {
        case (.iPhone, _): "Its microphones together, so your voice isn’t lost when one is covered."
        case (.bluetooth, true): "Not connected. Used when it is, at call quality."
        case (.bluetooth, false): "Call-quality sound on it while the mic is on."
        case (.other, true): "Not connected. Used when it is."
        case (.other, false): nil
        }
    }
}
