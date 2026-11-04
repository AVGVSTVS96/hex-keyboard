import Foundation
import KeyboardCore
import notify

/// The hours you typed, as counts, one JSON line each, appended each time a keyboard closes or a message goes. iOS can
/// run the keyboard in two apps at once, so each only ever appends, in one write, and none can lose another's. With
/// Full Access the lines go under the App Group's Library for the app's Stats, after any the keyboard kept in its own
/// container while it had none.
public enum TypingStats {
    nonisolated private static let changed = "com.shahidy.hexkeyboard.typing"

    nonisolated private static var ownURL: URL {
        URL.applicationSupportDirectory.appending(path: "typing.jsonl")
    }

    nonisolated private static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "Library/typing.jsonl")
    }

    /// Appends at once rather than on a queue: iOS suspends a keyboard the moment its app goes away, before queued
    /// work runs, and a few hundred bytes take no time.
    static func save(_ hours: [TypingHour], sharing: Bool) {
        guard !hours.isEmpty else { return }
        let encoder = JSONEncoder()
        let lines = Data(hours.compactMap { try? encoder.encode($0) + [UInt8(ascii: "\n")] }.joined())
        guard sharing, let sharedURL else {
            append(lines, to: ownURL)
            return
        }
        if let kept = try? Data(contentsOf: ownURL), append(kept, to: sharedURL) { try? FileManager.default.removeItem(at: ownURL) }
        if append(lines, to: sharedURL) { notify_post(changed) }
    }

    @discardableResult nonisolated private static func append(_ data: Data, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = open(url.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard file >= 0 else { return false }
        defer { close(file) }
        return data.withUnsafeBytes { write(file, $0.baseAddress, $0.count) } == data.count
    }

    /// Every hour the keyboard has shared, oldest first.
    nonisolated public static func shared() -> [TypingHour] {
        guard let data = sharedURL.flatMap({ try? Data(contentsOf: $0) }) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(TypingHour.self, from: $0) }
    }

    public static func delete() {
        if let sharedURL { try? FileManager.default.removeItem(at: sharedURL) }
        notify_post(changed)
    }

    /// Calls `handler` on the main queue each time a keyboard shares new hours, until the token is cancelled.
    public static func observe(_ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(changed, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }
}
