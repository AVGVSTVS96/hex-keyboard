import Foundation
import KeyboardCore
import os

/// The next-word network fine-tuned on your typing: the server makes it from its record of what you type (`scripts/personal`,
/// docs/backup.md) and gives it back under `personal/en.network`. The app fetches it whenever it syncs into the App Group's
/// `Personal/` folder, outside `Library` so it isn't sent back, and the keyboard reads it from there in place of the bundled
/// one. It never leaves the server and this iPhone.
nonisolated public enum PersonalNetwork {
    private static let name = "personal/en.network"
    private static let forgottenKey = "personalNetworkForgottenAt"
    private static let log = Logger(subsystem: "com.shahidy.hexkeyboard", category: "personal")

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "Personal/en.network")
    }

    /// The fetched network, read in place, or nil when there is none or it isn't one.
    public static func load() -> Network? {
        guard let url, let bytes = Bytes.mapped(url) else { return nil }
        return Network(bytes: bytes)
    }

    /// Fetches the server's network when it's another than the one here and made after the last reset.
    public static func fetch() async {
        guard let url else { return log.notice("no App Group, so no personal network") }
        let forgotten = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: forgottenKey))
        log.notice("personal network: \(String(describing: await Backup.pull(name, to: url, after: forgotten)), privacy: .public)")
    }

    /// Removes the copy here, and takes none the server made before now: a reset starts over from the bundled network.
    public static func forget() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: forgottenKey)
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
