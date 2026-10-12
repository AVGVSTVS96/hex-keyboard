import KeyboardCore
import KeyboardUI
import UIKit

enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    private static func integer(_ key: String) -> Int? {
        defaults.string(forKey: key).flatMap { Int($0) }
    }

    static var focus: Bool { defaults.bool(forKey: "HexFocus") }
    static var settings: Bool { defaults.bool(forKey: "HexSettings") }
    static var taps: Bool { defaults.bool(forKey: "HexTaps") }
    static var tapsAccuracy: Bool { defaults.string(forKey: "HexTapsMode") == "accuracy" }
    static var tapsKey: String? { defaults.string(forKey: "HexTapsKey") }
    static var orientation: UIInterfaceOrientationMask? {
        switch defaults.string(forKey: "HexOrientation") {
        case "landscape": .landscapeRight
        case "portrait": .portrait
        default: nil
        }
    }

    static func resetSettingsIfAsked() {
        guard defaults.bool(forKey: "HexResetSettings") else { return }
        SettingsStore.toggles.forEach { SettingsStore.defaults.removeObject(forKey: $0.key) }
        SettingsStore.set(OneHanded.off)
        MemoryStore.reset()
    }

    static func applyOneHanded() {
        if let hand = defaults.string(forKey: "HexOneHanded").flatMap(OneHanded.init) { SettingsStore.set(hand) }
    }

    static func configure(_ field: UITextView) {
        if let value = integer("HexKeyboardType").flatMap(UIKeyboardType.init) { field.keyboardType = value }
        if let value = integer("HexReturnKey").flatMap(UIReturnKeyType.init) { field.returnKeyType = value }
        if let text = defaults.string(forKey: "HexText") { field.text = text }
    }
}
