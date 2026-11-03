import Foundation
import KeyboardCore

/// Settings travel from the app to the keyboard through the App Group, but iOS deletes the group's container whenever
/// an install leaves no app claiming the group, and the keyboard can write it only with Full Access. So each side also
/// keeps its own copy of every value and takes the group's only when the group holds one it hasn't seen: a missing
/// value changes nothing, and a side that may write the group puts its copy back.
public enum SettingsStore {
    public static let appGroup = "group.com.shahidy.hexkeyboard"

    public static let toggles: [(key: String, path: WritableKeyPath<KeyboardSettings, Bool>)] = [
        ("autoCapitalization", \.autoCapitalization),
        ("autoCorrection", \.autoCorrection),
        ("capsLock", \.capsLock),
        ("smartPunctuation", \.smartPunctuation),
        ("periodShortcut", \.periodShortcut),
        ("predictiveText", \.predictiveText),
        ("sound", \.sound),
        ("emojiKey", \.emojiKey),
        ("numberRow", \.numberRow),
    ]

    /// The settings with a value picked from a list, each kept as its raw value. Character Preview and Haptic Feedback
    /// were switches under their old keys, which stand in until a new value is kept.
    private static let theme = Choice(key: "theme", path: \.theme)
    private static let themeAppearance = Choice(key: "themeAppearance", path: \.themeAppearance)
    private static let characterPreview = Choice(key: "characterPreviewStyle", path: \.characterPreview, switchKey: "characterPreview", on: .attached, off: CharacterPreview.none)
    private static let haptics = Choice(key: "hapticFeedback", path: \.haptics, switchKey: "haptics", on: .standard, off: .off)
    private static let skinToneKey = "skinTone"

    private static let oneHandedKey = "oneHanded"
    private static let keepMicOnKey = "keepMicOn"
    private static let dictationStyleKey = "dictationStyle"
    private static let keepsUmAndUhKey = "keepsUmAndUh"

    private static var group: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
    private static var own: UserDefaults { .standard }

    public static func load(sharing: Bool = true) -> KeyboardSettings {
        var settings = KeyboardSettings.initial
        for (key, path) in toggles {
            if let value = value(forKey: key, sharing: sharing) as? Bool { settings[keyPath: path] = value }
        }
        settings.oneHanded = (value(forKey: oneHandedKey, sharing: sharing) as? String).flatMap(OneHanded.init) ?? .off
        theme.load(into: &settings, sharing: sharing)
        themeAppearance.load(into: &settings, sharing: sharing)
        characterPreview.load(into: &settings, sharing: sharing)
        haptics.load(into: &settings, sharing: sharing)
        settings.skinTone = (value(forKey: skinToneKey, sharing: sharing) as? String).flatMap(SkinTone.init)
        return settings
    }

    /// Keeps every value of `settings`, for the app, which changes them one page at a time.
    public static func save(_ settings: KeyboardSettings) {
        for (key, path) in toggles { set(settings[keyPath: path], forKey: key) }
        set(settings.oneHanded)
        theme.save(settings)
        themeAppearance.save(settings)
        characterPreview.save(settings)
        haptics.save(settings)
        set(settings.skinTone?.rawValue ?? "", forKey: skinToneKey)
    }

    public static func set(_ value: Bool, for path: WritableKeyPath<KeyboardSettings, Bool>) {
        guard let key = toggles.first(where: { $0.path == path })?.key else { return }
        set(value, forKey: key)
    }

    public static func set(_ oneHanded: OneHanded, sharing: Bool = true) {
        set(oneHanded.rawValue, forKey: oneHandedKey, sharing: sharing)
    }

    /// Seconds the app keeps the microphone on after you dictate (`Dictation.micChoices`). Only the app reads it.
    public static var keepMicOn: Int {
        get { value(forKey: keepMicOnKey, sharing: true) as? Int ?? Dictation.micDefault }
        set { set(newValue, forKey: keepMicOnKey) }
    }

    /// How the app ends what you dictate. Only the app reads it.
    public static var dictationStyle: DictationStyle {
        get { (value(forKey: dictationStyleKey, sharing: true) as? String).flatMap(DictationStyle.init) ?? .standard }
        set { set(newValue.rawValue, forKey: dictationStyleKey) }
    }

    /// Whether the app types the um and uh you say. Only the app reads it.
    public static var keepsUmAndUh: Bool {
        get { value(forKey: keepsUmAndUhKey, sharing: true) as? Bool ?? true }
        set { set(newValue, forKey: keepsUmAndUhKey) }
    }

    /// Set by the keyboard whenever it opens with Allow Full Access, the only time it can write to the App Group, so the
    /// app can tell the setting is on. It stays set if you turn Full Access off later.
    public static var fullAccessSeen: Bool {
        get { group.bool(forKey: "fullAccessSeen") }
        set { group.set(newValue, forKey: "fullAccessSeen") }
    }

    /// Whether iOS let the keyboard read the clipboard the last time it tried (Settings › Apps › Hex › Paste from Other
    /// Apps), or nil before it has tried with Full Access.
    public static var pasteAllowed: Bool? {
        get { group.object(forKey: "pasteAllowed") as? Bool }
        set { group.set(newValue, forKey: "pasteAllowed") }
    }

    public static func reset(to settings: KeyboardSettings = .initial) {
        save(settings)
        keepMicOn = Dictation.micDefault
        dictationStyle = .standard
        keepsUmAndUh = true
    }

    static func value(forKey key: String, sharing: Bool) -> Any? {
        let seen = "seen." + key
        if let shared = group.object(forKey: key) as? NSObject {
            if !shared.isEqual(own.object(forKey: seen)) {
                own.set(shared, forKey: seen)
                own.set(shared, forKey: key)
            }
        } else if sharing, let mine = own.object(forKey: key) {
            group.set(mine, forKey: key)
            own.set(mine, forKey: seen)
        }
        return own.object(forKey: key)
    }

    static func set(_ value: Any, forKey key: String, sharing: Bool = true) {
        own.set(value, forKey: key)
        guard sharing else { return }
        group.set(value, forKey: key)
        own.set(value, forKey: "seen." + key)
    }
}

private struct Choice<Value: RawRepresentable<String>> {
    let key: String
    let path: WritableKeyPath<KeyboardSettings, Value>
    var switchKey: String?
    var on, off: Value?

    init(key: String, path: WritableKeyPath<KeyboardSettings, Value>, switchKey: String? = nil, on: Value? = nil, off: Value? = nil) {
        self.key = key
        self.path = path
        self.switchKey = switchKey
        self.on = on
        self.off = off
    }

    func load(into settings: inout KeyboardSettings, sharing: Bool) {
        if let value = (SettingsStore.value(forKey: key, sharing: sharing) as? String).flatMap({ Value(rawValue: $0) }) {
            settings[keyPath: path] = value
        } else if let switchKey, let old = SettingsStore.value(forKey: switchKey, sharing: sharing) as? Bool, let value = old ? on : off {
            settings[keyPath: path] = value
        }
    }

    func save(_ settings: KeyboardSettings) {
        SettingsStore.set(settings[keyPath: path].rawValue, forKey: key)
    }
}
