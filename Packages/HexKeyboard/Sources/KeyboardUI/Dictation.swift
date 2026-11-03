import Foundation
import notify

/// Voice typing runs in the app, because a keyboard can't use the microphone: the keyboard opens the app with a
/// `Request`, the app listens until the keyboard (or the app) says it's done, and leaves what it wrote down in the App
/// Group for the keyboard to type. Each side tells the other through a Darwin notification. The app alone writes the
/// `Status`, and leaves each `Note` in a file of its own that the keyboard takes by removing it, so the two never write
/// the same file.
public enum Dictation {
    /// What the app is doing. Recording and writing are separate: the app records a new dictation while the ones before
    /// are still being written down, and has them typed in the order you said them.
    public struct Status: Codable, Equatable, Sendable {
        public var listening = false
        /// When the newest dictation started, by the app recording it, so every keyboard that opens shows the same time.
        public var since: Date?
        /// How long each dictation the app has recorded and is still writing down is, in seconds, oldest first.
        public var writing: [Double] = []
        /// What those dictations wait for while the model gets ready, in a few words; nil once it's ready.
        public var waiting: String?

        public init(listening: Bool = false, since: Date? = nil, writing: [Double] = [], waiting: String? = nil) {
            self.listening = listening
            self.since = since
            self.writing = writing
            self.waiting = waiting
        }
    }

    /// What the app leaves for the keyboard.
    public enum Note: Codable, Equatable, Sendable {
        /// A dictation written down, typed only by the keyboard you stopped it in (`keyboard`, which it sent with
        /// `finish` or `stop`), so it never lands in a field you didn't say it for; one stopped in the app (its Done)
        /// is typed by the next keyboard to see it.
        case heard(String, keyboard: UInt64?)
        /// Something to tell you about a dictation: why it couldn't be made or written down, or where it went.
        case notice(String)
    }

    public enum Signal: String, Sendable {
        /// The app changed the status.
        case changed = "com.shahidy.hexkeyboard.dictation"
        /// The keyboard wants what was said so far, carrying its `keyboard` in the notification's state.
        case finish = "com.shahidy.hexkeyboard.dictation.finish"
        /// The keyboard wants to dictate again while the app still has the microphone on.
        case start = "com.shahidy.hexkeyboard.dictation.start"
        /// The keyboard wants the microphone off, with what was said so far typed, carrying its `keyboard` as `finish` does.
        case stop = "com.shahidy.hexkeyboard.dictation.stop"
        /// How loud you are, carried in the notification's state (`level`).
        case level = "com.shahidy.hexkeyboard.dictation.level"
    }

    /// How long the app may keep the microphone on after you dictate, in seconds, so the next dictation starts right
    /// on the keyboard instead of opening the app. Nothing is transcribed until you pick the mic again.
    public static let micChoices = [0, 30, 60, 300, 900, 3600, micForever]
    public static let micDefault = 300
    public static let micForever = Int.max

    public static func title(keepingMicOn seconds: Int) -> String {
        switch seconds {
        case ..<1: "Off"
        case ..<60: "\(seconds) Seconds"
        case 60: "1 Minute"
        case ..<3600: "\(seconds / 60) Minutes"
        case 3600: "1 Hour"
        case micForever: "Until Turned Off"
        default: "\(seconds / 3600) Hours"
        }
    }

    /// The link the keyboard opens the app with: dictate, then go back to `host`, the app you were typing in.
    public struct Request: Equatable, Sendable {
        public var host: String?

        public init(host: String?) {
            self.host = host
        }

        public init?(_ link: URL) {
            guard link.scheme == "hexkeyboard", link.host() == "dictate" else { return nil }
            host = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "host" }?.value
        }

        public var url: URL {
            let link = URL(string: "hexkeyboard://dictate")!
            return host.map { link.appending(queryItems: [URLQueryItem(name: "host", value: $0)]) } ?? link
        }
    }

    private static var library: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup)?.appending(path: "Library")
    }

    private static var statusURL: URL? { library?.appending(path: "dictation.json") }

    private static var micURL: URL? { library?.appending(path: "mic.lock") }

    private static var notesURL: URL? { library?.appending(path: "notes") }

    /// The app holds this lock while its microphone is on. The kernel lets go of it when the app ends however it ends,
    /// so the lock, unlike a status the app writes, can't outlive the app.
    public static func lockMic() -> Int32? {
        guard let micURL else { return nil }
        let descriptor = open(micURL.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    public static func unlockMic(_ descriptor: Int32) {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Whether the app has the microphone on, so `start` reaches it without opening it.
    public static var micIsOn: Bool {
        guard let micURL else { return false }
        let descriptor = open(micURL.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return flock(descriptor, LOCK_SH | LOCK_NB) != 0
    }

    public static var status: Status {
        statusURL.flatMap { try? JSONDecoder().decode(Status.self, from: Data(contentsOf: $0)) } ?? Status()
    }

    public static func publish(_ status: Status) {
        guard let statusURL else { return }
        try? JSONEncoder().encode(status).write(to: statusURL, options: .atomic)
        send(.changed)
    }

    /// Leaves a note for the keyboard, after the ones before it.
    public static func leave(_ note: Note) {
        guard let notesURL, let data = try? JSONEncoder().encode(note) else { return }
        try? FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)
        let name = String(format: "%020llu-%@.json", clock_gettime_nsec_np(CLOCK_REALTIME), UUID().uuidString)
        try? data.write(to: notesURL.appending(path: name), options: .atomic)
        send(.changed)
    }

    /// The notes the app has left, oldest first, each where `take` finds it.
    public static var notes: [(file: URL, note: Note)] {
        guard let notesURL, let files = try? FileManager.default.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Note.self, from: $0) }.map { (file, $0) }
        }
    }

    /// Takes a note, true for the one taker: removing its file succeeds once.
    public static func take(_ file: URL) -> Bool {
        (try? FileManager.default.removeItem(at: file)) != nil
    }

    public static func send(_ signal: Signal) {
        notify_post(signal.rawValue)
    }

    /// Sends `finish` or `stop` from `keyboard`, a number the keyboard picks each time it appears.
    public static func send(_ signal: Signal, from keyboard: UInt64) {
        if let token = stateTokens[signal] { notify_set_state(token, keyboard) }
        send(signal)
    }

    nonisolated private static let stateTokens = Dictionary(uniqueKeysWithValues: [Signal.finish, .stop].map { signal in
        var token: Int32 = 0
        notify_register_check(signal.rawValue, &token)
        return (signal, token)
    })

    nonisolated private static let levelToken: Int32 = {
        var token: Int32 = 0
        notify_register_check(Signal.level.rawValue, &token)
        return token
    }()

    /// The microphone's loudness (RMS of a buffer), for the keyboard's mic to move with your voice.
    nonisolated public static func publish(level: Float) {
        notify_set_state(levelToken, UInt64(level.bitPattern))
        notify_post(Signal.level.rawValue)
    }

    /// Calls `handler` on the main queue with each loudness the app publishes.
    public static func observeLevel(_ handler: @escaping @MainActor @Sendable (Float) -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(Signal.level.rawValue, &token, .main) { token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            MainActor.assumeIsolated { handler(Float(bitPattern: UInt32(truncatingIfNeeded: state))) }
        }
        return token
    }

    /// Calls `handler` on the main queue on each `signal`, until the token is cancelled with `stopObserving`.
    public static func observe(_ signal: Signal, _ handler: @escaping @MainActor @Sendable () -> Void) -> Int32 {
        observe(signal) { _ in handler() }
    }

    /// Calls `handler` on the main queue on each `signal` with the keyboard it came from, nil when none said.
    public static func observe(_ signal: Signal, _ handler: @escaping @MainActor @Sendable (_ keyboard: UInt64?) -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(signal.rawValue, &token, .main) { token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            MainActor.assumeIsolated { handler(state == 0 ? nil : state) }
        }
        return token
    }

    public static func stopObserving(_ token: Int32) {
        notify_cancel(token)
    }
}
