import KeyboardCore
import KeyboardUI
import SwiftUI

/// Every setting in the app, in one list: the keyboard's, voice typing's, and Hex's own, a page each. Wide, the list
/// takes the pane before the hinge and the picked page the one after; elsewhere a page opens on its own.
struct SettingsPage: View {
    enum Page: String, CaseIterable, Hashable {
        case theme, layout, typing, feedback, model, writing, dictionary, mic, sources, access, privacy, about

        static let sections: [(title: String, pages: [Page])] = [
            ("Keyboard", [.theme, .layout, .typing, .feedback]),
            ("Voice Typing", [.model, .writing, .dictionary, .mic]),
            ("Hex", [.sources, .access, .privacy, .about]),
        ]

        var title: String {
            switch self {
            case .theme: "Theme"
            case .layout: "Layout"
            case .typing: "Typing"
            case .feedback: "Sound & Haptics"
            case .model: "Voice Model"
            case .writing: "Writing Style"
            case .dictionary: "Dictionary"
            case .mic: "Keep Mic On"
            case .sources: "Sources"
            case .access: "Keyboard Access"
            case .privacy: "Privacy & Data"
            case .about: "About Hex"
            }
        }

        var glyph: (String, Color) {
            switch self {
            case .theme: ("paintpalette.fill", .purple)
            case .layout: ("keyboard.fill", .blue)
            case .typing: ("character.cursor.ibeam", .cyan)
            case .feedback: ("hand.tap.fill", .pink)
            case .model: ("waveform", .red)
            case .writing: ("textformat", .orange)
            case .dictionary: ("character.book.closed.fill", .brown)
            case .mic: ("mic.fill", .green)
            case .sources: ("antenna.radiowaves.left.and.right", .teal)
            case .access: ("switch.2", .indigo)
            case .privacy: ("hand.raised.fill", .blue)
            case .about: ("info", .gray)
            }
        }

        /// What the page is set to, beside it in the list and on Home's card for it.
        @MainActor var value: String? {
            let model = SettingsModel.shared, settings = model.settings, words = VoiceVocabulary.shared.vocabulary.terms.count
            return switch self {
            case .theme: settings.theme.title
            case .layout, .typing, .privacy: nil
            case .feedback: settings.haptics.title
            case .model: VoiceModel.shared.model.title
            case .writing: settings.dictationStyle.title
            case .dictionary: words == 1 ? "1 word" : "\(words.formatted()) words"
            case .mic: Dictation.title(keepingMicOn: model.keepMicOn)
            case .sources: model.sources.isEmpty ? "None" : model.sources.count.formatted()
            case .access: HexStatus.shared.isSetUp ? "All Set" : "Needs Setup"
            case .about: AboutPage.version
            }
        }

        /// The keyboard's pages show Hex drawn as their settings make it, with a field to try it.
        var showsKeyboard: Bool { [.theme, .layout, .typing, .feedback].contains(self) }
    }

    @Bindable private var router = Router.shared
    @Environment(\.arrangement) private var arrangement
    private let model = SettingsModel.shared

    private var beside: Bool { arrangement == .side }

    var body: some View {
        NavigationStack(path: beside ? .constant([]) : $router.settingsPath) {
            Group {
                if beside {
                    let picked = router.settingsPath.last ?? .theme
                    Panes {
                        SettingsList(picked: picked) { router.settingsPath = [$0] }
                    } second: {
                        SettingsContent(page: picked, top: 12).id(picked)
                    }
                } else {
                    SettingsList(picked: nil) { router.settingsPath = [$0] }
                        .navigationDestination(for: Page.self) { page in
                            SettingsContent(page: page, top: 8).pushedPage(page.title)
                        }
                }
            }
            .hexPage()
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
        .onAppear { model.reload() }
    }
}

/// The settings' pages under their sections, each with what it's set to; wide, the picked one is filled.
private struct SettingsList: View {
    typealias Page = SettingsPage.Page

    let picked: Page?
    let open: (Page) -> Void

    var body: some View {
        Column(top: 4) {
            ForEach(Page.sections, id: \.title) { section in
                Box(header: section.title) {
                    ForEach(section.pages, id: \.self) { page in
                        Button { open(page) } label: { row(page) }
                            .buttonStyle(.plain)
                            .background(page == picked ? Color.hexPressed : .clear)
                            .accessibilityIdentifier(page.rawValue)
                            .accessibilityAddTraits(page == picked ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func row(_ page: Page) -> some View {
        HStack(spacing: 14) {
            Glyph(symbol: page.glyph.0, color: page.glyph.1)
            Text(page.title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value = page.value {
                Text(value)
                    .foregroundStyle(Color.hexSecondary)
                    .lineLimit(1)
            }
            if picked == nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.hexSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(.rect)
    }
}

/// One settings page, on its own or in the pane after the hinge.
struct SettingsContent: View {
    let page: SettingsPage.Page
    var top: CGFloat = 8

    var body: some View {
        if page == .dictionary {
            VocabularyView()
        } else {
            Column(top: top) {
                if page.showsKeyboard { TryPreview() }
                switch page {
                case .theme: ThemeSettings()
                case .layout: LayoutSettings()
                case .typing: TypingSettings()
                case .feedback: FeedbackSettings()
                case .model: ModelSettings()
                case .writing: WritingSettings()
                case .dictionary: EmptyView()
                case .mic: MicSettings()
                case .sources: SourcesPage()
                case .access: SetupPage()
                case .privacy: PrivacyPage()
                case .about: AboutPage()
                }
            }
        }
    }
}
