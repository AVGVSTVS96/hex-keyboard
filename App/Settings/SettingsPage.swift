import KeyboardStore
import KeyboardCore
import KeyboardUI
import SwiftUI

/// Every setting in the app, in one list: the keyboard's, voice typing's, and iikb's own, a page each. Wide, the list
/// takes the first pane and the picked page the second; elsewhere a page opens on its own.
struct SettingsPage: View {
    enum Page: String, CaseIterable, Hashable {
        case appearance, typing, feedback, voice, writing, dictionary, sources, access, privacy, changelog, about

        static let sections: [(title: String, pages: [Page])] = [
            ("Keyboard", [.appearance, .typing, .feedback]),
            ("Voice Typing", [.voice, .writing, .dictionary]),
            ("iikb", [.sources, .access, .privacy, .changelog, .about]),
        ]

        var title: String {
            switch self {
            case .appearance: "Appearance"
            case .typing: "Typing"
            case .feedback: ThisDevice.hasHaptics ? "Sound & Haptics" : "Sound"
            case .voice: "Voice"
            case .writing: "Writing Style"
            case .dictionary: "Dictionary"
            case .sources: "Sources"
            case .access: "Keyboard Access"
            case .privacy: "Privacy & Data"
            case .changelog: "Changelog"
            case .about: "About iikb"
            }
        }

        var glyph: (String, Color) {
            switch self {
            case .appearance: ("paintpalette.fill", .purple)
            case .typing: ("character.cursor.ibeam", .cyan)
            case .feedback: (ThisDevice.hasHaptics ? "hand.tap.fill" : "speaker.wave.2.fill", .pink)
            case .voice: ("waveform", .red)
            case .writing: ("textformat", .orange)
            case .dictionary: ("character.book.closed.fill", .brown)
            case .sources: ("antenna.radiowaves.left.and.right", .teal)
            case .access: ("switch.2", .indigo)
            case .privacy: ("hand.raised.fill", .blue)
            case .changelog: ("clock.arrow.circlepath", .orange)
            case .about: ("info", .gray)
            }
        }

        /// What the page is set to, beside it in the list and on Home's card for it.
        @MainActor var value: String? {
            let model = SettingsModel.shared, settings = model.settings, words = VoiceVocabulary.shared.vocabulary.terms.count
            return switch self {
            case .appearance: settings.theme.title
            case .typing, .privacy, .changelog: nil
            case .feedback: ThisDevice.hasHaptics ? settings.haptics.title : settings.sound ? "On" : "Off"
            case .voice: VoiceModel.shared.model.title
            case .writing: settings.dictationStyle.title
            case .dictionary: words == 1 ? "1 word" : "\(words.formatted()) words"
            case .sources: model.sources.isEmpty ? "None" : model.sources.count.formatted()
            case .access: AppStatus.shared.isSetUp ? "All Set" : "Needs Setup"
            case .about: AboutPage.version
            }
        }

        /// The keyboard's pages show iikb drawn as their settings make it, with a field to try it.
        var showsKeyboard: Bool { [.appearance, .typing, .feedback].contains(self) }
    }

    @Bindable private var router = Router.shared
    @Environment(\.arrangement) private var arrangement
    private let model = SettingsModel.shared

    private var beside: Bool { arrangement == .side }

    var body: some View {
        NavigationStack(path: beside ? .constant([]) : $router.settingsPath) {
            Group {
                if beside {
                    let picked = router.settingsPath.last ?? .appearance
                    Panes(list: true) {
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
            .appPage()
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
                            .background(page == picked ? Color.appPressed : .clear)
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
                    .foregroundStyle(Color.appSecondary)
                    .lineLimit(1)
            }
            if picked == nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(.rect)
    }
}

/// One settings page, on its own or in the second pane.
struct SettingsContent: View {
    let page: SettingsPage.Page
    var top: CGFloat = 8

    var body: some View {
        Column(top: top) {
            if page.showsKeyboard { TryPreview() }
            switch page {
            case .appearance: AppearanceSettings()
            case .typing: TypingSettings()
            case .feedback: FeedbackSettings()
            case .voice: VoiceSettings()
            case .writing: WritingSettings()
            case .dictionary: VocabularyView()
            case .sources: SourcesPage()
            case .access: SetupPage()
            case .privacy: PrivacyPage()
            case .changelog: ChangelogPage()
            case .about: AboutPage()
            }
        }
    }
}
