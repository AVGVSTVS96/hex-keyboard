import KeyboardStore
import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "iikbFocus") }
    /// `-iikbScrollToEnd YES` opens every page scrolled to its end, for screenshots of what sits above the tab bar.
    static var scrollsToEnd: Bool { defaults.bool(forKey: "iikbScrollToEnd") }
    static var scrollAnchor: UnitPoint { scrollsToEnd ? .bottom : .top }
    /// The tab and page the app opens on: `-iikbTab transcripts`, `-iikbTaps YES` for Stats' Taps, `-iikbStats dictation`
    /// for another of its pills, `-iikbSettings typing` for a settings page (`YES` for the list), as `SettingsPage.Page`
    /// names them.
    static func route() {
        let router = Router.shared
        if let section = statsSection { return router.show(section) }
        if let page = defaults.string(forKey: "iikbSettings") { return router.show(.settings, settings: SettingsPage.Page(rawValue: page)) }
        router.show(defaults.string(forKey: "iikbTab").flatMap(Router.Destination.init) ?? .home)
    }

    static var statsSection: StatsPage.Section? {
        defaults.bool(forKey: "iikbTaps") ? .taps : defaults.string(forKey: "iikbStats").flatMap(StatsPage.Section.init)
    }
    /// `-iikbStatsDevice mac` shows the Mac's.
    static var statsDevice: StatsPage.Device? { defaults.string(forKey: "iikbStatsDevice").flatMap(StatsPage.Device.init) }

    static var tapsMode: TapMapView.Mode? {
        switch defaults.string(forKey: "iikbTapsMode") {
        case "heat": .heat
        case "aim": .aim
        case "accuracy": .accuracy
        default: nil
        }
    }
    static var tapsScroll: String? { defaults.string(forKey: "iikbTapsScroll") }
    static var tapsKey: String? { defaults.string(forKey: "iikbTapsKey") }
    static var orientation: UIInterfaceOrientationMask? {
        switch defaults.string(forKey: "iikbOrientation") {
        case "landscape": .landscapeRight
        case "portrait": .portrait
        default: nil
        }
    }

    /// `-iikbResetSettings YES` puts back Apple's keyboard settings, which the UI tests are written against, and forgets
    /// what iikb learned.
    static func resetSettingsIfAsked() {
        guard defaults.bool(forKey: "iikbResetSettings") else { return }
        SettingsStore.reset(to: KeyboardSettings())
        MemoryStore.reset()
    }

    /// `-iikbOneHanded left`, `-iikbCompactPanels YES`, `-iikbAutoCapitalization YES` and `-iikbMicKey YES` set those
    /// settings for a test.
    static func applySettings() {
        if let hand = defaults.string(forKey: "iikbOneHanded").flatMap(OneHanded.init) { SettingsStore.set(hand) }
        if defaults.object(forKey: "iikbCompactPanels") != nil { SettingsStore.set(defaults.bool(forKey: "iikbCompactPanels"), for: \.compactPanels) }
        if defaults.object(forKey: "iikbAutoCapitalization") != nil { SettingsStore.set(defaults.bool(forKey: "iikbAutoCapitalization"), for: \.autoCapitalization) }
        if defaults.object(forKey: "iikbMicKey") != nil { SettingsStore.set(defaults.bool(forKey: "iikbMicKey"), for: \.micKey) }
    }

    /// `-iikbTheme mechanical -iikbThemeAppearance dark -iikbCharacterPreview detached -iikbNumberRow YES -iikbSkinTone medium
    /// -iikbKeySpacing tighter -iikbKeyRoundness rounder` set the keyboard's look for screenshots.
    static func applyLook() {
        var settings = SettingsStore.load()
        if let theme = defaults.string(forKey: "iikbTheme").flatMap(ThemeName.init) { settings.theme = theme }
        if let appearance = defaults.string(forKey: "iikbThemeAppearance").flatMap(ThemeAppearance.init) { settings.themeAppearance = appearance }
        if let preview = defaults.string(forKey: "iikbCharacterPreview").flatMap(CharacterPreview.init) { settings.characterPreview = preview }
        if defaults.object(forKey: "iikbNumberRow") != nil { settings.numberRow = defaults.bool(forKey: "iikbNumberRow") }
        if let tone = defaults.string(forKey: "iikbSkinTone") { settings.skinTone = SkinTone(rawValue: tone) }
        if let spacing = defaults.string(forKey: "iikbKeySpacing").flatMap(KeySpacing.init) { settings.keySpacing = spacing }
        if let roundness = defaults.string(forKey: "iikbKeyRoundness").flatMap(KeyRoundness.init) { settings.keyRoundness = roundness }
        if settings != SettingsStore.load() { SettingsStore.save(settings) }
    }

    static func configure(_ field: UITextView) {
        if let value = integer("FullKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("iikbReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "iikbText") { field.text = text }
        if defaults.bool(forKey: "iikbSends") { sends(field) }
    }

    /// `-iikbSends YES`: return sends, emptying the field wherever the caret is, as a messaging app does, for
    /// scripts/edittest.
    private static func sends(_ field: UITextView) {
        field.returnKeyType = .send
        field.delegate = sender
    }

    @MainActor private static let sender = Sender()

    private final class Sender: NSObject, UITextViewDelegate {
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            textView.text = ""
            return false
        }
    }
}
