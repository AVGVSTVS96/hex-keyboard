import KeyboardUI

extension Backup {
    /// Sends the app's files and the group's in the background.
    static func syncApp() {
        sync(app + group, skip: unwritten)
    }

    /// Sends the app's files and the group's and says how it went.
    static func sendApp() async -> Outcome? {
        await send(app + group, skip: unwritten)
    }

    /// Recordings still being made, which go once written down.
    private static var unwritten: @Sendable (String) -> Bool {
        let written = Set(Transcripts.shared.all.map { "app/recordings/\($0.id.uuidString).wav" })
        return { $0.hasPrefix("app/recordings/") && !written.contains($0) }
    }
}
