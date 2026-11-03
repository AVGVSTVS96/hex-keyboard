import KeyboardCore
import KeyboardUI
import SwiftUI

/// The keyboard's settings, after Raycast's Keyboard page: Hex drawn as it will look, with a field to try it, and the
/// settings in pills beside it, a page per subject.
struct KeyboardPage: View {
    enum Tab: String, CaseIterable, Hashable {
        case theme, typing, keys, voice, sound

        var title: String {
            switch self {
            case .theme: "Theme"
            case .typing: "Typing"
            case .keys: "Keys"
            case .voice: "Voice"
            case .sound: "Sound & Haptics"
            }
        }
    }

    @Bindable private var router = Router.shared
    @Environment(\.arrangement) private var arrangement
    private let model = SettingsModel.shared

    var body: some View {
        Group {
            switch arrangement {
            case .side, .stacked:
                Panes(share: 0.42) {
                    VStack(alignment: .leading, spacing: 0) {
                        PageTitle(title: "Keyboard")
                            .padding(.top, 12)
                        Spacer(minLength: 16)
                        TryPreview()
                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 16)
                } second: {
                    VStack(alignment: .leading, spacing: 14) {
                        Pills(items: Tab.allCases, selection: $router.keyboardPage, title: \.title)
                            .padding(.top, arrangement == .side ? 12 : 0)
                            .padding(.horizontal, 12)
                        Column(top: 4) { content }
                    }
                }
            case .single:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        PageTitle(title: "Keyboard")
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        TryPreview()
                            .padding(16)
                        Section {
                            VStack(alignment: .leading, spacing: 28) { content }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 40)
                        } header: {
                            Pills(items: Tab.allCases, selection: $router.keyboardPage, title: \.title)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.hexPage)
                        }
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .hexPage()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.reload() }
    }

    @ViewBuilder private var content: some View {
        switch router.keyboardPage {
        case .theme: ThemeSettings()
        case .typing: TypingSettings()
        case .keys: KeysSettings()
        case .voice: VoiceSettings()
        case .sound: SoundSettings()
        }
    }
}

/// A field to try the keyboard in, so a change can be felt at once.
private struct TryPreview: View {
    @State private var text = ""

    var body: some View {
        TextField("Type to try Hex", text: $text, axis: .vertical)
            .font(.title3)
            .lineLimit(4 ... 8)
            .padding(18)
            .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
    }
}

/// What the settings pages read and write: the keyboard's switches through `SettingsStore`, so the keyboard and
/// Settings › Apps › Hex see the same values, and the sources Hex tells what you type.
@Observable final class SettingsModel {
    static let shared = SettingsModel()

    private(set) var settings = SettingsStore.load()
    private(set) var sources = SourceStore.load()
    private(set) var keepMicOn = SettingsStore.keepMicOn
    private(set) var dictationStyle = SettingsStore.dictationStyle

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsModel.shared.reload() }
        }
    }

    func reload() {
        settings = SettingsStore.load()
        sources = SourceStore.load()
        keepMicOn = SettingsStore.keepMicOn
        dictationStyle = SettingsStore.dictationStyle
    }

    func binding(_ path: WritableKeyPath<KeyboardSettings, Bool>) -> Binding<Bool> {
        Binding { self.settings[keyPath: path] } set: {
            self.settings[keyPath: path] = $0
            SettingsStore.set($0, for: path)
        }
    }

    var oneHanded: OneHanded {
        get { settings.oneHanded }
        set {
            settings.oneHanded = newValue
            SettingsStore.set(newValue)
        }
    }

    func keepMicOn(_ seconds: Int) {
        keepMicOn = seconds
        SettingsStore.keepMicOn = seconds
        Listener.shared.keepMicOn()
    }

    func dictationStyle(_ style: DictationStyle) {
        dictationStyle = style
        SettingsStore.dictationStyle = style
    }

    /// Adds a source, or puts `replacing` back with its new values.
    func save(_ source: Source, replacing old: Source?) {
        var sources = SourceStore.load()
        if let old, let index = sources.firstIndex(of: old) { sources[index] = source } else { sources.append(source) }
        SourceStore.save(sources)
        self.sources = sources
    }

    func delete(_ offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        SourceStore.save(sources)
    }

    func move(_ offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        SourceStore.save(sources)
    }
}

private struct ThemeSettings: View {
    var body: some View {
        Box(footer: "More themes are on their way.") {
            ChoiceRow(title: "Default", picked: true) {}
        }
    }
}

private struct TypingSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(footer: "Predictive Text shows three suggestions above the keys, and the next word before you type it.") {
            ToggleRow(title: "Auto-Capitalization", isOn: model.binding(\.autoCapitalization))
            ToggleRow(title: "Auto-Correction", isOn: model.binding(\.autoCorrection))
            ToggleRow(title: "Predictive Text", isOn: model.binding(\.predictiveText))
        }
        Box(footer: "Smart Punctuation curls quotes and turns two hyphens into a dash.") {
            ToggleRow(title: "Smart Punctuation", isOn: model.binding(\.smartPunctuation))
            ToggleRow(title: "Enable Caps Lock", detail: "Double-tap shift.", isOn: model.binding(\.capsLock))
            ToggleRow(title: "“.” Shortcut", detail: "Double-tap space for a period and a space.", isOn: model.binding(\.periodShortcut))
        }
        Box(header: "Text Replacements") {
            Button { HexStatus.openSettings() } label: {
                HStack {
                    RowText(title: "From iOS Settings", detail: "Hex types the ones in Settings › General › Keyboard › Text Replacement.")
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.hexSecondary)
                }
                .row()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct KeysSettings: View {
    private let model = SettingsModel.shared

    var body: some View {
        Box(header: "Bottom Row") {
            ToggleRow(title: "Emoji Key", detail: "Every emoji, from beside the space bar. Without it, a word’s emoji still show in the suggestions.", isOn: model.binding(\.emojiKey))
        }
        Box(header: "Pressing a Key") {
            ToggleRow(title: "Character Preview", detail: "The letter shows bigger above your thumb.", isOn: model.binding(\.characterPreview))
        }
        Box(header: "One-Handed Keyboard", footer: "Moves the keys toward one thumb while the iPhone is upright. You can also hold 123 and slide.") {
            ForEach(OneHanded.allCases, id: \.self) { hand in
                ChoiceRow(title: Self.title(of: hand), picked: model.oneHanded == hand) { model.oneHanded = hand }
            }
        }
    }

    static func title(of hand: OneHanded) -> String {
        switch hand {
        case .off: "Off"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

private struct SoundSettings: View {
    private let model = SettingsModel.shared
    private let status = HexStatus.shared

    var body: some View {
        Box(footer: status.fullAccess ? nil : "Haptics need Allow Full Access.") {
            ToggleRow(title: "Haptic Feedback", detail: "Each key taps back, as Apple’s keyboard does.", isOn: model.binding(\.haptics))
            ToggleRow(title: "Sound", detail: "The key click, while Keyboard Clicks is on in iOS Settings › Sounds & Haptics.", isOn: model.binding(\.sound))
            if !status.fullAccess {
                ActionRow(title: "Allow Full Access", symbol: "arrow.up.forward") { HexStatus.openSettings() }
            }
        }
    }
}

struct VoiceSettings: View {
    private let model = SettingsModel.shared
    private let voice = VoiceModel.shared

    var body: some View {
        Box(header: "Voice Model", footer: "What you say is written on this iPhone and never leaves it. Until the model you pick is ready, Apple’s writes.") {
            ForEach(VoiceModel.Model.allCases, id: \.self) { choice in
                ChoiceRow(title: choice.title, detail: choice.detail, picked: choice == voice.model) {
                    voice.pick(choice)
                } extra: {
                    if choice == voice.model, voice.state != .ready { progress }
                }
            }
        }
        Box(header: "Style", footer: "As Said types every word, um and uh included. The others leave those out and change only capitals and periods. Transcripts keeps what the model wrote.") {
            ForEach(DictationStyle.allCases, id: \.self) { style in
                ChoiceRow(title: style.title, detail: style.example, picked: model.dictationStyle == style) { model.dictationStyle(style) }
            }
        }
        Box(header: "Keep Mic On", footer: "After you dictate, Hex keeps the mic on this long, so the mic beside the suggestions starts and stops without leaving your app. Hold it to turn the mic off.") {
            ForEach(Dictation.micChoices, id: \.self) { seconds in
                ChoiceRow(title: Dictation.title(keepingMicOn: seconds), picked: model.keepMicOn == seconds) { model.keepMicOn(seconds) }
            }
        }
        Box(footer: "The words the voice model gets wrong, each with what it writes instead.") {
            LinkRow(title: "Vocabulary", value: VoiceVocabulary.shared.vocabulary.terms.count.formatted(), symbol: ("character.book.closed.fill", .orange)) {
                VocabularyView()
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
