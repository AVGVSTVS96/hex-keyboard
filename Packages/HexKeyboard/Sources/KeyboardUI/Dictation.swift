import Foundation
import notify

/// Voice typing runs in the app, because a keyboard can't use the microphone: the keyboard opens the app with `url`,
/// the app listens until the keyboard (or the app) says it's done, and leaves what it heard in the App Group for the
/// keyboard to type. Each side tells the other through a Darwin notification and reads the shared status on it.
public enum Dictation {
    public enum State: String, Codable, Sendable {
        case idle, listening, transcribing
    }

    public struct Status: Codable, Equatable, Sendable {
        public var state = State.idle
        /// What the app heard, until the keyboard types it.
        public var heard: String?
        public var failure: String?

        public init(state: State = .idle, heard: String? = nil, failure: String? = nil) {
            self.state = state
            self.heard = heard
            self.failure = failure
        }
    }

    public enum Signal: String, Sendable {
        /// The app changed the status.
        case changed = "com.shahidy.hexkeyboard.dictation"
        /// The keyboard wants what was said so far.
        case finish = "com.shahidy.hexkeyboard.dictation.finish"
        /// The keyboard wants nothing typed.
        case cancel = "com.shahidy.hexkeyboard.dictation.cancel"
    }

    public static let url = URL(string: "hexkeyboard://dictate")!

    private static var statusURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "Library/dictation.json")
    }

    public static var status: Status {
        statusURL.flatMap { try? JSONDecoder().decode(Status.self, from: Data(contentsOf: $0)) } ?? Status()
    }

    public static func publish(_ status: Status) {
        guard let statusURL else { return }
        try? JSONEncoder().encode(status).write(to: statusURL, options: .atomic)
        send(.changed)
    }

    public static func send(_ signal: Signal) {
        notify_post(signal.rawValue)
    }

    /// Calls `handler` on the main queue on each `signal`, until the token is cancelled with `stopObserving`.
    public static func observe(_ signal: Signal, _ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(signal.rawValue, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }

    public static func stopObserving(_ token: Int32) {
        notify_cancel(token)
    }
}
