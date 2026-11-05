import Foundation
import KeyboardCore
import notify

/// Settings travel from the app to the keyboard through the App Group, but iOS deletes the group's container whenever
/// an install leaves no app claiming the group, and the keyboard can write it only with Full Access. So each side also
/// keeps its own copy of every value and takes the group's only when the group holds one it hasn't seen: a missing
/// value changes nothing, and a side that may write the group puts its copy back. The app tells a keyboard that's up
/// with a Darwin notification each time it keeps them, as on the open iPhone Duo, where the app sits beside the keys.
public enum SettingsStore {
    public static let toggles: [(key: String, path: WritableKeyPath<KeyboardSettings, Bool>)] = [
        ("autoCapitalization", \.autoCapitalization),
        ("autoCorrection", \.autoCorrection),
        ("capsLock", \.capsLock),
        ("smartPunctuation", \.smartPunctuation),
        ("periodShortcut", \.periodShortcut),
        ("predictiveText", \.predictiveText),
        ("slideToType", \.slideToType),
        ("sound", \.sound),
        ("emojiKey", \.emojiKey),
        ("micKey", \.micKey),
        ("numberRow", \.numberRow),
        ("split", \.split),
        ("compactPanels", \.compactPanels),
    ]

    /// The settings with a value picked from a list, each kept as its raw value. Character Preview and Haptic Feedback
    /// were switches under their old keys, which stand in until a new value is kept.
    private static let theme = Choice(key: "theme", path: \.theme)
    private static let themeAppearance = Choice(key: "themeAppearance", path: \.themeAppearance)
    private static let characterPreview = Choice(key: "characterPreviewStyle", path: \.characterPreview, switchKey: "characterPreview", on: .attached, off: CharacterPreview.none)
    private static let haptics = Choice(key: "hapticFeedback", path: \.haptics, switchKey: "haptics", on: .standard, off: .off)
    private static let keySpacing = Choice(key: "keySpacing", path: \.keySpacing)
    private static let keyRoundness = Choice(key: "keyRoundness", path: \.keyRoundness)
    private static let dictationStyle = Choice(key: "writingStyle", path: \.dictationStyle)
    private static let dictationEditing = Choice(key: "dictationEditing", path: \.dictationEditing, switchKey: "keepsUmAndUh", on: .asSaid, off: .light)
    private static let dictationLists = Choice(key: "spokenLists", path: \.dictationLists, switchKey: "dictationLists", on: .numbered, off: .off)
    private static let keyboardMenu = Choice(key: "keyboardMenu", path: \.keyboardMenu)
    /// Globe Key was a switch, turned off to stop taps landing on the globe, which Spacer now does with the globe kept.
    private static let globeKey = Choice(key: "globe", path: \.globeKey, switchKey: "globeKey", on: .switches, off: .spacer)
    private static let skinToneKey = "skinTone"

    private static let oneHandedKey = "oneHanded"
    private static let keepMicOnKey = "keepMicOn"
    private static let microphoneKey = "microphone"

    private static var group: UserDefaults { UserDefaults(suiteName: AppGroup.id) ?? .standard }
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
        keySpacing.load(into: &settings, sharing: sharing)
        keyRoundness.load(into: &settings, sharing: sharing)
        dictationStyle.load(into: &settings, sharing: sharing)
        dictationEditing.load(into: &settings, sharing: sharing)
        dictationLists.load(into: &settings, sharing: sharing)
        keyboardMenu.load(into: &settings, sharing: sharing)
        globeKey.load(into: &settings, sharing: sharing)
        settings.skinTone = (value(forKey: skinToneKey, sharing: sharing) as? String).flatMap(SkinTone.init)
        return settings
    }

    /// Keeps every value of `settings`, for the app, which changes them one page at a time.
    public static func save(_ settings: KeyboardSettings) {
        defer { notify_post(changed) }
        for (key, path) in toggles { set(settings[keyPath: path], forKey: key) }
        set(settings.oneHanded)
        theme.save(settings)
        themeAppearance.save(settings)
        characterPreview.save(settings)
        haptics.save(settings)
        keySpacing.save(settings)
        keyRoundness.save(settings)
        dictationStyle.save(settings)
        dictationEditing.save(settings)
        dictationLists.save(settings)
        keyboardMenu.save(settings)
        globeKey.save(settings)
        set(settings.skinTone?.rawValue ?? "", forKey: skinToneKey)
    }

    private static let changed = "com.shahidy.iikb.settings"

    /// Calls `handler` on the main queue each time the app keeps the settings, until the token is cancelled with
    /// `Dictation.stopObserving`.
    public static func observe(_ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(changed, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }

    public static func set(_ value: Bool, for path: WritableKeyPath<KeyboardSettings, Bool>, sharing: Bool = true) {
        guard let key = toggles.first(where: { $0.path == path })?.key else { return }
        set(value, forKey: key, sharing: sharing)
    }

    public static func set(_ oneHanded: OneHanded, sharing: Bool = true) {
        set(oneHanded.rawValue, forKey: oneHandedKey, sharing: sharing)
    }

    /// Seconds the app keeps the microphone on after you dictate (`Dictation.micChoices`). Only the app reads it.
    public static var keepMicOn: Int {
        get { value(forKey: keepMicOnKey, sharing: true) as? Int ?? Dictation.micDefault }
        set { set(newValue, forKey: keepMicOnKey) }
    }

    /// The microphone picked to dictate with, nil to leave it to iikb's automatic choice. Only the app reads it.
    public static var microphone: PickedMicrophone? {
        get { (value(forKey: microphoneKey, sharing: true) as? [String: String]).flatMap(PickedMicrophone.init) }
        set { set(newValue?.stored ?? [:], forKey: microphoneKey) }
    }

    public static func reset(to settings: KeyboardSettings = .initial) {
        save(settings)
        keepMicOn = Dictation.micDefault
        microphone = nil
    }

    package static func value(forKey key: String, sharing: Bool) -> Any? {
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

    package static func set(_ value: Any, forKey key: String, sharing: Bool = true) {
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
        if let raw = SettingsStore.value(forKey: key, sharing: sharing) as? String {
            if let value = Value(rawValue: raw) { settings[keyPath: path] = value }
        } else if let switchKey, let old = SettingsStore.value(forKey: switchKey, sharing: sharing) as? Bool, let value = old ? on : off {
            settings[keyPath: path] = value
        }
    }

    func save(_ settings: KeyboardSettings) {
        SettingsStore.set(settings[keyPath: path].rawValue, forKey: key)
    }
}

/// A microphone picked in the app, kept by its port's UID and the name it had, so it stays picked while it's away.
public struct PickedMicrophone: Hashable, Sendable {
    public enum Kind: String, Sendable { case iPhone, bluetooth, other }

    public let uid: String
    public let name: String
    public let kind: Kind

    public init(uid: String, name: String, kind: Kind) {
        self.uid = uid
        self.name = name
        self.kind = kind
    }

    init?(_ stored: [String: String]) {
        guard let uid = stored["uid"], let name = stored["name"] else { return nil }
        self.init(uid: uid, name: name, kind: stored["kind"].flatMap(Kind.init) ?? .other)
    }

    var stored: [String: String] { ["uid": uid, "name": name, "kind": kind.rawValue] }
}
