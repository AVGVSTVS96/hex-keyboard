import OSLog
import UIKit

/// The app you were typing in when the keyboard opened Hex, so voice typing can send you back to it.
///
/// Since iOS 26.4 a keyboard can't learn its host, but UIKit in the app it opens still receives the keyboard's source
/// app in `_UIRemoteKeyboards.currentState`, about a second after the link, and clears it soon after, so it's watched
/// from launch. Neither that nor `LSApplicationWorkspace` is API: when a step is missing, `host` answers nil and the
/// dictation screen stays up for you to swipe back.
@MainActor final class HostApp: NSObject {
    static let shared = HostApp()
    static let log = Logger(subsystem: "com.shahidy.hexkeyboard", category: "voice")

    private var keyboards: NSObject?
    private var latest: (bundle: String, at: Date)?
    private var waiters: [UUID: CheckedContinuation<String?, Never>] = [:]

    func watch() {
        guard keyboards == nil,
              let type = NSClassFromString("_UIRemoteKeyboards") as? NSObject.Type,
              let shared = type.perform(NSSelectorFromString("sharedRemoteKeyboards"))?.takeUnretainedValue() as? NSObject,
              shared.responds(to: NSSelectorFromString("currentState"))
        else { return }
        keyboards = shared
        shared.addObserver(self, forKeyPath: "currentState", options: [.initial, .new], context: nil)
    }

    /// The app that last showed the keyboard, if it did after `since`, waiting up to `timeout` for it.
    func host(since: Date, timeout: Duration = .seconds(2)) async -> String? {
        if let latest, latest.at >= since { return latest.bundle }
        guard keyboards != nil else { return nil }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task {
                try? await Task.sleep(for: timeout)
                waiters.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    /// Opens the app by its bundle ID, or where iOS won't, by its own link.
    func open(_ bundle: String) async -> Bool {
        if openByID(bundle) { return true }
        guard let link = Self.links[bundle].flatMap(URL.init(string:)) else { return false }
        Self.log.notice("opening \(bundle, privacy: .public) by link")
        return await UIApplication.shared.open(link)
    }

    private func openByID(_ bundle: String) -> Bool {
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
              workspace.responds(to: selector)
        else { return false }
        typealias Open = @convention(c) (NSObject, Selector, NSString) -> Bool
        return unsafeBitCast(workspace.method(for: selector), to: Open.self)(workspace, selector, bundle as NSString)
    }

    /// From OpenWhispr's `HostAppCatalog` (MIT), which returns to these apps this way on iOS 26.
    private static let links = [
        "ph.telegra.Telegraph": "tg://",
        "net.whatsapp.WhatsApp": "whatsapp://send",
        "com.apple.MobileSMS": "sms://",
        "com.apple.mobilemail": "message://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.mobilesafari": "x-web-search://",
        "com.atebits.Tweetie2": "twitter://",
        "com.hammerandchisel.discord": "discord://",
        "com.tinyspeck.chatlyio": "slack://",
        "com.google.Gmail": "googlegmail://",
        "com.google.chrome.ios": "googlechrome://",
        "com.burbn.instagram": "instagram://",
        "com.facebook.Messenger": "fb-messenger://",
        "org.whispersystems.signal": "sgnl://",
        "com.openai.chat": "chatgpt://",
        "notion.id": "notion://",
    ]

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let selector = NSSelectorFromString("sourceBundleIdentifier")
        let state = change?[.newKey] as? NSObject
        let bundle = state?.responds(to: selector) == true ? state?.perform(selector)?.takeUnretainedValue() as? String : nil
        let at = Date.now
        Task { @MainActor in HostApp.shared.record(bundle, at: at) }
    }

    private func record(_ bundle: String?, at: Date) {
        guard let bundle, !bundle.isEmpty, bundle != Bundle.main.bundleIdentifier else { return }
        latest = (bundle, at)
        Self.log.notice("keyboard host \(bundle, privacy: .public)")
        for continuation in waiters.values { continuation.resume(returning: bundle) }
        waiters = [:]
    }
}
