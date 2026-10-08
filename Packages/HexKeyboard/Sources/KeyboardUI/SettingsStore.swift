import Foundation
import KeyboardCore

public enum SettingsStore {
    public static let appGroup = "group.com.shahidy.hexkeyboard"

    public static let toggles: [(key: String, path: WritableKeyPath<KeyboardSettings, Bool>)] = [
        ("autoCapitalization", \.autoCapitalization),
        ("autoCorrection", \.autoCorrection),
        ("capsLock", \.capsLock),
        ("smartPunctuation", \.smartPunctuation),
        ("periodShortcut", \.periodShortcut),
        ("predictiveText", \.predictiveText),
        ("characterPreview", \.characterPreview),
        ("sound", \.sound),
    ]

    public static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    public static func load() -> KeyboardSettings {
        var settings = KeyboardSettings()
        for (key, path) in toggles {
            if let value = defaults.object(forKey: key) as? Bool { settings[keyPath: path] = value }
        }
        return settings
    }

    public static func set(_ value: Bool, for path: WritableKeyPath<KeyboardSettings, Bool>) {
        guard let key = toggles.first(where: { $0.path == path })?.key else { return }
        defaults.set(value, forKey: key)
    }
}
