import KeyboardCore
import KeyboardUI
import SwiftUI

struct SourcesPage: View {
    private let model = SettingsModel.shared
    @State private var editing: Source?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !model.sources.isEmpty {
                Box(header: "Your Sources") {
                    ForEach(model.sources, id: \.self) { source in
                        Button { editing = source } label: {
                            HStack {
                                RowText(title: source.name, detail: source.url.host() ?? source.url.absoluteString)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.hexSecondary)
                            }
                            .row()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Box(footer: "A source is a service you run that iikb tells what you type. With Full Access on, each one gets the app’s bundle ID and the text of the field you’re typing in, never passwords or codes, and can answer with a hint above the keys. Tap a hint to hide it.") {
                ActionRow(title: "Add Source", symbol: "plus") { adding = true }
            }
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
            Column {
                Box(footer: problem ?? "iikb sends the token with each update, so the source can tell it’s you.") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .row()
                    TextField("https://", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .row()
                    SecureField("Token (optional)", text: $token)
                        .textInputAutocapitalization(.never)
                        .row()
                }
                if let source {
                    Box {
                        ActionRow(title: "Delete Source", role: .destructive) {
                            if let index = SettingsModel.shared.sources.firstIndex(of: source) { SettingsModel.shared.delete([index]) }
                            dismiss()
                        }
                    }
                }
            }
            .pushedPage(source == nil ? "Add Source" : "Edit Source")
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
        .presentationBackground(Color.hexPage)
    }
}

/// The switches iOS keeps for Hex, each checked when Hex can tell.
struct SetupSteps: View {
    private let status = HexStatus.shared

    var body: some View {
        SetupStep(done: status.isAdded, title: "Add iikb", detail: status.isAdded ? "iikb is one of your keyboards." : "Turn on Keyboards › iikb.")
        SetupStep(done: status.fullAccess, title: "Allow Full Access", detail: "For voice typing, haptics, GIFs, the clipboard, sources and your taps.")
        SetupStep(done: status.pasteAllowed, title: "Paste from Other Apps", detail: "Set it to Allow, so the clipboard keeps what you copy.")
    }
}

private struct SetupStep: View {
    let done: Bool
    let title: String
    let detail: String

    var body: some View {
        Button { HexStatus.openSettings() } label: {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.hexSecondary)
                    .accessibilityHidden(true)
                RowText(title: title, detail: detail)
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.hexSecondary)
                    .accessibilityHidden(true)
            }
            .row()
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

struct SetupPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Box(footer: "iOS keeps these in Settings › Apps › iikb. iikb checks each one off once the keyboard has seen it on; if you turn one off later, iikb can’t tell.") {
                SetupSteps()
            }
            Box {
                ActionRow(title: "Open iikb in Settings", symbol: "arrow.up.forward") { HexStatus.openSettings() }
            }
        }
    }
}

struct PrivacyPage: View {
    @State private var confirmsReset = false
    @State private var confirmsDelete = false
    @State private var confirmsDeleteTyping = false
    @State private var backup: Backup.Outcome?
    private let transcripts = Transcripts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Box(header: "What Leaves This iPhone") {
                Label(Backup.isBuiltIn ? "Learned words, app-specific language and emoji choices, typing counts, dictations and clipboard history stay here and on your backup server." : "Learned words, app-specific language and emoji choices, typing counts, dictations and clipboard history stay here.", systemImage: "iphone").row()
                Label("iikb goes online to download its voice model, search GIFs, and send the field’s text and app ID to sources you add.", systemImage: "network").row()
            }
            if Backup.isBuiltIn {
                Box(header: "Backup", footer: "iikb sends what it keeps to your server each time it changes, and the server keeps every version, so a lost iPhone, a reinstall or a bug can’t take it.") {
                    switch backup {
                    case nil: RowText(title: "Checking your server…").row()
                    case .upToDate: RowText(title: "Up to date", detail: "Your dictations, Dictionary, clipboard and taps are there. The keyboard sends what it learns each time it closes.").row()
                    case .unreachable: RowText(title: "Can’t reach your server", detail: "iikb sends what changed the next time it can.").row()
                    }
                }
                .task { backup = await Backup.sendApp() }
            }
            Box(footer: "iikb forgets the words it learned across apps and within each app, and where your thumbs land on each key. Your Dictionary stays.") {
                ActionRow(title: "Reset Learned Words and Taps", role: .destructive) { confirmsReset = true }
            }
            Box(footer: "Deletes the counts Stats keeps of your typing on this iPhone: never what you typed, only how much, how fast and in which app.") {
                ActionRow(title: "Delete Typing Stats", role: .destructive) { confirmsDeleteTyping = true }
            }
            Box(footer: transcripts.all.isEmpty ? "You haven’t dictated anything yet." : "Deletes all \(transcripts.all.count.formatted()) dictations and their sound from this iPhone.") {
                ActionRow(title: "Delete All Transcripts", role: .destructive) { confirmsDelete = true }
                    .disabled(transcripts.all.isEmpty)
            }
        }
        .confirmationDialog("iikb will forget the words it learned and everything it learned about your taps.", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { MemoryStore.reset() }
        }
        .confirmationDialog("Delete your typing stats from this iPhone?", isPresented: $confirmsDeleteTyping, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { TypingStats.delete() }
        }
        .confirmationDialog("Delete all \(transcripts.all.count) transcripts from this iPhone?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { transcripts.delete(Set(transcripts.all.map(\.id))) }
        }
    }
}

struct AboutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) {
                Mark(size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iikb").font(.display(28)).tracking(-0.045 * 28)
                    Text(Self.version).foregroundStyle(Color.hexSecondary)
                }
            }
            .padding(.horizontal, 4)
            Box(footer: "iikb types like Apple’s keyboard and learns where your thumbs land. It’s open source, under the MIT license.") {
                Link(destination: URL(string: "https://github.com/AVGVSTVS96/iikb")!) {
                    HStack {
                        Text("Source Code").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color.hexSecondary)
                    }
                    .row()
                }
            }
            Box {
                Link(destination: URL(string: "https://github.com/AVGVSTVS96/iikb/blob/main/Packages/HexKeyboard/Sources/KeyboardUI/Resources/SWIPE-LICENSE")!) {
                    HStack {
                        Text("Swipe typing powered by FUTO Swipe").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color.hexSecondary)
                    }
                    .row()
                }
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}
