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
        ("haptics", \.haptics),
        ("sound", \.sound),
    ]

    public static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    public static func load() -> KeyboardSettings {
        var settings = KeyboardSettings()
        for (key, path) in toggles {
            if let value = defaults.object(forKey: key) as? Bool { settings[keyPath: path] = value }
        }
        settings.oneHanded = oneHanded
        return settings
    }

    private static let oneHandedKey = "oneHanded"
    private static let seenOneHandedKey = "seenOneHanded"

    /// The keyboard switches hands itself but can write the App Group only with Full Access, so each side keeps its own
    /// copy and adopts the group's value whenever it changed since that side last saw it.
    private static var oneHanded: OneHanded {
        let own = UserDefaults.standard
        let shared = defaults.string(forKey: oneHandedKey)
        if shared != own.string(forKey: seenOneHandedKey) {
            own.set(shared, forKey: seenOneHandedKey)
            own.set(shared, forKey: oneHandedKey)
        }
        return own.string(forKey: oneHandedKey).flatMap(OneHanded.init) ?? .off
    }

    public static func set(_ oneHanded: OneHanded, sharing: Bool = true) {
        UserDefaults.standard.set(oneHanded.rawValue, forKey: oneHandedKey)
        guard sharing else { return }
        defaults.set(oneHanded.rawValue, forKey: oneHandedKey)
        UserDefaults.standard.set(oneHanded.rawValue, forKey: seenOneHandedKey)
    }

    public static func set(_ value: Bool, for path: WritableKeyPath<KeyboardSettings, Bool>) {
        guard let key = toggles.first(where: { $0.path == path })?.key else { return }
        defaults.set(value, forKey: key)
    }
}
