import KeyboardCore
import KeyboardUI
import SwiftUI

/// The keyboard's settings, a page per subject as in Settings: a list of pages beside the open page on the iPhone Duo's
/// open screen, one after the other on its cover.
struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case typing, keys, feedback, voice, sources, setup, privacy

        var id: Self { self }

        var title: String {
            switch self {
            case .typing: "Typing"
            case .keys: "Keys"
            case .feedback: "Sound & Haptics"
            case .voice: "Voice Typing"
            case .sources: "Sources"
            case .setup: "Keyboard Access"
            case .privacy: "Privacy & Data"
            }
        }

        var glyph: (symbol: String, color: Color) {
            switch self {
            case .typing: ("textformat", .blue)
            case .keys: ("keyboard.fill", .gray)
            case .feedback: ("speaker.wave.2.fill", .pink)
            case .voice: ("waveform", .red)
            case .sources: ("antenna.radiowaves.left.and.right", .teal)
            case .setup: ("switch.2", .green)
            case .privacy: ("hand.raised.fill", .indigo)
            }
        }

        static let groups: [[Page]] = [[.typing, .keys, .feedback], [.voice, .sources], [.privacy]]
    }

    @State var page: Page?
    @State private var columns = NavigationSplitViewVisibility.all
    @Environment(\.horizontalSizeClass) private var width
    private let model = SettingsModel.shared
    private let status = HexStatus.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $page) {
                Section {
                    NavigationLink(value: Page.setup) { header }
                        .accessibilityIdentifier(Page.setup.rawValue)
                        .hexList(selected: isSelected(.setup))
                }
                ForEach(Page.groups, id: \.self) { group in
                    Section {
                        ForEach(group) { page in
                            NavigationLink(value: page) {
                                Label {
                                    Text(page.title)
                                } icon: {
                                    Glyph(symbol: page.glyph.symbol, color: page.glyph.color)
                                }
                            }
                            .accessibilityIdentifier(page.rawValue)
                            .hexList(selected: isSelected(page))
                        }
                    }
                }
                Section {} footer: {
                    Text(Self.version)
                        .frame(maxWidth: .infinity)
                }
            }
            .hexBackground()
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 300, ideal: 340)
        } detail: {
            NavigationStack {
                if let page {
                    PageView(page: page)
                } else {
                    ContentUnavailableView("Pick a Setting", systemImage: "gearshape")
                        .hexBackground()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.accentColor)
        .onAppear {
            model.reload()
            if width == .regular, page == nil { page = .typing }
        }
        .onChange(of: width) { _, width in
            if width == .regular, page == nil { page = .typing }
        }
    }

    /// Only a sidebar beside its page shows which page is open.
    private func isSelected(_ page: Page) -> Bool {
        width == .regular && self.page == page
    }

    private var header: some View {
        HStack(spacing: 14) {
            HexMark(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Hex Keyboard")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.isAdded ? (status.fullAccess ? Color.green : Color.yellow) : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(status.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.hexSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "Hex \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}

/// What the settings pages read and write: the keyboard's switches through `SettingsStore`, so the keyboard and
/// Settings › Apps › Hex see the same values, and the sources Hex tells what you type.
@Observable final class SettingsModel {
    static let shared = SettingsModel()

    private(set) var settings = SettingsStore.load()
    private(set) var sources = SourceStore.load()
    private(set) var keepMicOn = SettingsStore.keepMicOn

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsModel.shared.reload() }
        }
    }

    func reload() {
        settings = SettingsStore.load()
        sources = SourceStore.load()
        keepMicOn = SettingsStore.keepMicOn
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

private struct PageView: View {
    let page: SettingsView.Page

    var body: some View {
        Group {
            switch page {
            case .typing: TypingPage()
            case .keys: KeysPage()
            case .feedback: FeedbackPage()
            case .voice: VoicePage()
            case .sources: SourcesPage()
            case .setup: SetupPage()
            case .privacy: PrivacyPage()
            }
        }
        .hexBackground()
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TypingPage: View {
    private let model = SettingsModel.shared

    var body: some View {
        List {
            Section {
                Toggle("Auto-Capitalization", isOn: model.binding(\.autoCapitalization))
                Toggle("Auto-Correction", isOn: model.binding(\.autoCorrection))
                Toggle("Predictive Text", isOn: model.binding(\.predictiveText))
            } footer: {
                Text("Predictive Text shows three suggestions above the keys, and the next word before you type it.")
            }
            .hexList()
            Section {
                Toggle("Smart Punctuation", isOn: model.binding(\.smartPunctuation))
                Toggle("Enable Caps Lock", isOn: model.binding(\.capsLock))
                Toggle("“.” Shortcut", isOn: model.binding(\.periodShortcut))
            } footer: {
                Text("Smart Punctuation curls quotes and turns two hyphens into a dash. Double tap shift for caps lock, and the space bar for a period and a space.")
            }
            .hexList()
            Section {} footer: {
                Text("Hex types your Text Replacements from Settings › General › Keyboard › Text Replacement.")
            }
        }
    }
}

private struct KeysPage: View {
    @Bindable private var model = SettingsModel.shared

    var body: some View {
        List {
            Section {
                Toggle("Character Preview", isOn: model.binding(\.characterPreview))
            } footer: {
                Text("Shows the letter bigger above your thumb as you press it.")
            }
            .hexList()
            Section {
                Picker("One-Handed Keyboard", selection: $model.oneHanded) {
                    ForEach(OneHanded.allCases, id: \.self) { hand in
                        Text(Self.title(of: hand)).tag(hand)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("One-Handed Keyboard")
            } footer: {
                Text("Moves the keys toward one thumb while the iPhone is upright. You can also hold 123 and slide, and tap the arrow beside the keys to bring them back.")
            }
            .hexList()
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

private struct FeedbackPage: View {
    private let model = SettingsModel.shared
    private let status = HexStatus.shared

    var body: some View {
        List {
            Section {
                Toggle("Haptic Feedback", isOn: model.binding(\.haptics))
            } footer: {
                Text(status.fullAccess ? "Each key taps back, as Apple’s keyboard does." : "Each key taps back, as Apple’s keyboard does, once Hex has Full Access.")
            }
            .hexList()
            Section {
                Toggle("Sound", isOn: model.binding(\.sound))
            } footer: {
                Text("Plays the key click while Keyboard Clicks is on in Settings › Sounds & Haptics.")
            }
            .hexList()
            if !status.fullAccess {
                Section {
                    Button("Allow Full Access") { HexStatus.openSettings() }
                }
                .hexList()
            }
        }
    }
}

private struct VoicePage: View {
    private let model = SettingsModel.shared
    private let voice = VoiceModel.shared

    var body: some View {
        List {
            Section {
                ForEach(VoiceModel.Model.allCases, id: \.self) { choice in
                    Button {
                        voice.pick(choice)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(choice.title)
                                    .foregroundStyle(.primary)
                                Text(choice.detail)
                                    .font(.footnote)
                                    .foregroundStyle(Color.hexSecondary)
                                if choice == voice.model, voice.state != .ready {
                                    progress
                                }
                            }
                            Spacer(minLength: 0)
                            if choice == voice.model {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == voice.model ? .isSelected : [])
                }
            } header: {
                Text("Voice Model")
            } footer: {
                Text("What you say is written down on this iPhone and never leaves it. Until the model you pick is ready, Apple’s writes, and Transcripts shows which one wrote each dictation.")
            }
            .hexList()
            Section {
                Picker("Keep Mic On", selection: Binding { model.keepMicOn } set: { model.keepMicOn($0) }) {
                    ForEach(Dictation.micChoices, id: \.self) { seconds in
                        Text(Dictation.title(keepingMicOn: seconds)).tag(seconds)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Keep Mic On")
            } footer: {
                Text("After you dictate, Hex keeps the mic on this long, so the mic beside the suggestions starts and stops dictating without leaving your app. Hold it to turn the mic off. Nothing is recorded until you tap it.")
            }
            .hexList()
            Section {
                NavigationLink {
                    VocabularyView()
                } label: {
                    LabeledContent("Vocabulary", value: VoiceVocabulary.shared.vocabulary.terms.count.formatted())
                }
            } footer: {
                Text("The words the voice model gets wrong, each with what it writes instead.")
            }
            .hexList()
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
            .padding(.top, 4)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Getting ready")
            }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
            .padding(.top, 4)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn’t get it ready: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Try Again") { voice.retry() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.top, 4)
        case .ready:
            EmptyView()
        }
    }
}

private struct SourcesPage: View {
    private let model = SettingsModel.shared
    @State private var editing: Source?
    @State private var adding = false

    var body: some View {
        List {
            if !model.sources.isEmpty {
                Section {
                    ForEach(model.sources, id: \.self) { source in
                        Button {
                            editing = source
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .foregroundStyle(.primary)
                                Text(source.url.host() ?? source.url.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(Color.hexSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: model.delete)
                    .onMove(perform: model.move)
                }
                .hexList()
            }
            Section {
                Button("Add Source", systemImage: "plus") { adding = true }
            } footer: {
                Text("A source is a service you run that Hex tells what you type. With Full Access on, each one gets the text of the field you’re typing in, never passwords or codes, and can answer with a hint above the keys. Tap a hint to hide it.")
            }
            .hexList()
        }
        .toolbar {
            if !model.sources.isEmpty { EditButton() }
        }
        .sheet(isPresented: $adding) { SourceForm(source: nil) }
        .sheet(item: $editing) { SourceForm(source: $0) }
    }
}

extension Source: @retroactive Identifiable {
    public var id: String { name + url.absoluteString }
}

/// A source's name, address and token, checked before it's saved.
private struct SourceForm: View {
    let source: Source?
    @State private var name: String
    @State private var address: String
    @State private var token: String
    @Environment(\.dismiss) private var dismiss

    init(source: Source?) {
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _address = State(initialValue: source?.url.absoluteString ?? "https://")
        _token = State(initialValue: source?.token ?? "")
    }

    private var url: URL? {
        URL(string: address.trimmingCharacters(in: .whitespaces)).flatMap { Source.allows($0) && $0.host() != nil ? $0 : nil }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var problem: String? {
        if trimmedName.isEmpty { return nil }
        if SettingsModel.shared.sources.contains(where: { $0.name == trimmedName && $0 != source }) { return "You already have a source called “\(trimmedName)”." }
        if url == nil, address.count > "https://".count { return "The address needs to start with https://." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("https://", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token (optional)", text: $token)
                        .textInputAutocapitalization(.never)
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else {
                        Text("Hex sends the token with each update, so the source can tell it’s you.")
                    }
                }
                .hexList()
                if let source {
                    Section {
                        Button("Delete Source", role: .destructive) {
                            if let index = SettingsModel.shared.sources.firstIndex(of: source) { SettingsModel.shared.delete([index]) }
                            dismiss()
                        }
                    }
                    .hexList()
                }
            }
            .hexBackground()
            .navigationTitle(source == nil ? "Add Source" : "Edit Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let url else { return }
                        SettingsModel.shared.save(Source(name: trimmedName, url: url, token: token.isEmpty ? nil : token), replacing: source)
                        dismiss()
                    }
                    .disabled(url == nil || trimmedName.isEmpty || problem != nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The switches iOS keeps for Hex, each checked when Hex can tell.
struct SetupSteps: View {
    private let status = HexStatus.shared

    var body: some View {
        SetupStep(done: status.isAdded, title: "Add Hex", detail: status.isAdded ? "Hex is one of your keyboards." : "Turn on Keyboards › Hex.")
        SetupStep(done: status.fullAccess, title: "Allow Full Access", detail: "For voice typing, haptics, GIFs, the clipboard, sources and your taps.")
        SetupStep(done: status.pasteAllowed, title: "Paste from Other Apps", detail: status.pasteAllowed == false ? "Set it to Allow, so the clipboard keeps what you copy." : "Set it to Allow, for the clipboard.")
    }
}

private struct SetupStep: View {
    let done: Bool?
    let title: String
    let detail: String

    var body: some View {
        Button { HexStatus.openSettings() } label: {
            HStack(spacing: 14) {
                Image(systemName: done == true ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done == true ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.hexSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.hexSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(done == true ? "Done" : "Not done")
    }
}

private struct SetupPage: View {
    var body: some View {
        List {
            Section {
                SetupSteps()
            } footer: {
                Text("iOS keeps these in Settings › Apps › Hex. Hex checks each one off once the keyboard has seen it on; if you turn one off later, Hex can’t tell.")
            }
            .hexList()
            Section {
                Button("Open Hex in Settings", systemImage: "arrow.up.forward.app") { HexStatus.openSettings() }
            }
            .hexList()
        }
    }
}

private struct PrivacyPage: View {
    @State private var confirmsReset = false
    @State private var confirmsDelete = false
    private let transcripts = Transcripts.shared

    var body: some View {
        List {
            Section {
                Label("What you type, say and copy stays on this iPhone.", systemImage: "iphone")
                Label("Hex goes online only to download its voice model once, search GIFs, and reach the sources you add.", systemImage: "network")
            }
            .foregroundStyle(.primary)
            .hexList()
            Section {
                Button("Reset Learned Words and Taps", role: .destructive) { confirmsReset = true }
            } footer: {
                Text("Hex forgets the words it learned from you and where your thumbs land on each key.")
            }
            .hexList()
            Section {
                Button("Delete All Transcripts", role: .destructive) { confirmsDelete = true }
                    .disabled(transcripts.all.isEmpty)
            } footer: {
                Text(transcripts.all.isEmpty ? "You haven’t dictated anything yet." : "Deletes all \(transcripts.all.count.formatted()) dictations from this iPhone.")
            }
            .hexList()
        }
        .confirmationDialog("Hex will forget the words it learned and everything it learned about your taps.", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { MemoryStore.reset() }
        }
        .confirmationDialog("Delete all \(transcripts.all.count) transcripts from this iPhone?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { transcripts.delete(Set(transcripts.all.map(\.id))) }
        }
    }
}
