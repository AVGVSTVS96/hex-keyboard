import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "HexFocus") }
    /// `-HexScrollToEnd YES` opens every page scrolled to its end, for screenshots of what sits above the tab bar.
    static var scrollsToEnd: Bool { defaults.bool(forKey: "HexScrollToEnd") }
    static var scrollAnchor: UnitPoint { scrollsToEnd ? .bottom : .top }
    /// The tab and page the app opens on: `-HexTab transcripts`, `-HexTaps YES` for Your Taps, `-HexSettings typing`
    /// for a settings page (`YES` for the list), as `SettingsPage.Page` names them.
    static func route() {
        let router = Router.shared
        if defaults.bool(forKey: "HexTaps") { return router.show(.taps) }
        if let page = defaults.string(forKey: "HexSettings") { return router.show(.settings, settings: SettingsPage.Page(rawValue: page)) }
        router.show(defaults.string(forKey: "HexTab").flatMap(Router.Destination.init) ?? .home)
    }

    static var tapsMode: TapMapView.Mode? {
        switch defaults.string(forKey: "HexTapsMode") {
        case "heat": .heat
        case "aim": .aim
        case "accuracy": .accuracy
        default: nil
        }
    }
    static var tapsScroll: String? { defaults.string(forKey: "HexTapsScroll") }
    static var tapsKey: String? { defaults.string(forKey: "HexTapsKey") }
    static var orientation: UIInterfaceOrientationMask? {
        switch defaults.string(forKey: "HexOrientation") {
        case "landscape": .landscapeRight
        case "portrait": .portrait
        default: nil
        }
    }

    /// `-HexResetSettings YES` puts back Apple's keyboard settings, which the UI tests are written against, and forgets
    /// what Hex learned.
    static func resetSettingsIfAsked() {
        guard defaults.bool(forKey: "HexResetSettings") else { return }
        SettingsStore.reset(to: KeyboardSettings())
        MemoryStore.reset()
    }

    /// `-HexOneHanded left` and `-HexCompactPanels YES` set those settings for a test.
    static func applySettings() {
        if let hand = defaults.string(forKey: "HexOneHanded").flatMap(OneHanded.init) { SettingsStore.set(hand) }
        if defaults.object(forKey: "HexCompactPanels") != nil { SettingsStore.set(defaults.bool(forKey: "HexCompactPanels"), for: \.compactPanels) }
    }

    /// `-HexTheme mechanical -HexThemeAppearance dark -HexCharacterPreview detached -HexNumberRow YES -HexSkinTone medium
    /// -HexKeySpacing tightest` set the keyboard's look for screenshots.
    static func applyLook() {
        var settings = SettingsStore.load()
        if let theme = defaults.string(forKey: "HexTheme").flatMap(ThemeName.init) { settings.theme = theme }
        if let appearance = defaults.string(forKey: "HexThemeAppearance").flatMap(ThemeAppearance.init) { settings.themeAppearance = appearance }
        if let preview = defaults.string(forKey: "HexCharacterPreview").flatMap(CharacterPreview.init) { settings.characterPreview = preview }
        if defaults.object(forKey: "HexNumberRow") != nil { settings.numberRow = defaults.bool(forKey: "HexNumberRow") }
        if let tone = defaults.string(forKey: "HexSkinTone") { settings.skinTone = SkinTone(rawValue: tone) }
        if let spacing = defaults.string(forKey: "HexKeySpacing").flatMap(KeySpacing.init) { settings.keySpacing = spacing }
        if settings != SettingsStore.load() { SettingsStore.save(settings) }
    }

    static func configure(_ field: UITextView) {
        if let value = integer("HexKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("HexReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "HexText") { field.text = text }
    }
}
