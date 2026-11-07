import OSLog
import UIKit

/// Opens the app you were typing in, which the keyboard names in its `Dictation.Request`. `LSApplicationWorkspace`
/// isn't API: where it won't open the app by its bundle ID, the app's own link does, and with neither the dictation
/// screen stays up for you to swipe back.
enum HostApp {
    nonisolated static let log = Logger(subsystem: "com.shahidy.iikb", category: "voice")

    /// The megabytes iikb has written to storage since it started, as iOS counts them against its disk-writes limit.
    nonisolated static var written: Double {
        var usage = rusage_info_v4()
        return rusage(getpid(), RUSAGE_INFO_V4, &usage) == 0 ? Double(usage.ri_logical_writes) / 1_000_000 : 0
    }

    #if APP_STORE
    nonisolated private static func rusage(_ pid: pid_t, _ flavor: Int32, _ usage: UnsafeMutableRawPointer) -> Int32 { -1 }
    #else
    /// libproc's `proc_pid_rusage`, in iOS's libSystem but not its SDK's headers.
    @_silgen_name("proc_pid_rusage")
    nonisolated private static func rusage(_ pid: pid_t, _ flavor: Int32, _ usage: UnsafeMutableRawPointer) -> Int32
    #endif

    static func open(_ bundle: String) async -> Bool {
        if openByID(bundle) { return true }
        guard let link = links[bundle].flatMap(URL.init(string:)) else { return false }
        log.notice("opening \(bundle, privacy: .public) by link")
        return await UIApplication.shared.open(link)
    }

    private static func openByID(_ bundle: String) -> Bool {
        #if APP_STORE
        return false
        #else
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
              workspace.responds(to: selector)
        else { return false }
        typealias Open = @convention(c) (NSObject, Selector, NSString) -> Bool
        return unsafeBitCast(workspace.method(for: selector), to: Open.self)(workspace, selector, bundle as NSString)
        #endif
    }

    /// Links that bring each app back where you were rather than performing an action, from Dictus's `KnownAppSchemes`
    /// (MIT), which measured them: Messages comes back to the conversation only by `ichat://` (`sms://` opens a new
    /// message), and every Safari link opens a blank page or search, so Safari has none.
    private static let links = [
        "ph.telegra.Telegraph": "tg://",
        "net.whatsapp.WhatsApp": "whatsapp-consumer://",
        "com.apple.MobileSMS": "ichat://",
        "com.apple.mobilemail": "message://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.reminders": "x-apple-reminderkit://",
        "com.atebits.Tweetie2": "twitter://",
        "com.hammerandchisel.discord": "discord://",
        "com.tinyspeck.chatlyio": "slack://open",
        "com.google.Gmail": "googlegmail://",
        "com.google.chrome.ios": "googlechrome://",
        "com.burbn.instagram": "instagram://",
        "com.facebook.Messenger": "fb-messenger://",
        "org.whispersystems.signal": "sgnl://",
        "com.openai.chat": "com.openai.chat://",
        "com.anthropic.claude": "claude://",
        "com.t3tools.t3code": "t3code://",
        "com.github.stormbreaker.prod": "github://",
        "notion.id": "notion://",
    ]
}
