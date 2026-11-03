import KeyboardCore
import KeyboardUI
import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "HexFocus") }
    /// The tab and page the app opens on: `-HexTab keyboard`, `-HexTaps YES` for Your Taps, `-HexSettings typing` for a
    /// Keyboard page (`YES` for its first), `-HexSettings voice` for Voice's settings, or `-HexSettings sources` for a
    /// page under More.
    static func route() {
        let router = Router.shared
        if defaults.bool(forKey: "HexTaps") { return router.show(.taps) }
        if let page = defaults.string(forKey: "HexSettings") {
            let aliases = ["keys": "layout", "sound": "feedback"]
            if let keyboard = KeyboardPage.Tab(rawValue: aliases[page] ?? page) { return router.show(.keyboard, page: keyboard) }
            if page == "voice" { return router.show(.voice, voice: .settings) }
            if let more = MorePage.Page(rawValue: page) {
                router.morePath = [more]
                return router.show(.more)
            }
            return router.show(.keyboard)
        }
        let tab = defaults.string(forKey: "HexTab")
        router.show(tab == "transcripts" ? .voice : tab.flatMap(Router.Destination.init) ?? .home)
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

    /// `-HexTheme mechanical -HexThemeAppearance dark -HexCharacterPreview detached -HexNumberRow YES -HexSkinTone medium`
    /// set the keyboard's look for screenshots.
    static func applyLook() {
        var settings = SettingsStore.load()
        if let theme = defaults.string(forKey: "HexTheme").flatMap(ThemeName.init) { settings.theme = theme }
        if let appearance = defaults.string(forKey: "HexThemeAppearance").flatMap(ThemeAppearance.init) { settings.themeAppearance = appearance }
        if let preview = defaults.string(forKey: "HexCharacterPreview").flatMap(CharacterPreview.init) { settings.characterPreview = preview }
        if defaults.object(forKey: "HexNumberRow") != nil { settings.numberRow = defaults.bool(forKey: "HexNumberRow") }
        if let tone = defaults.string(forKey: "HexSkinTone") { settings.skinTone = SkinTone(rawValue: tone) }
        if settings != SettingsStore.load() { SettingsStore.save(settings) }
    }

    static func configure(_ field: UITextView) {
        if let value = integer("HexKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("HexReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "HexText") { field.text = text }
    }
}
