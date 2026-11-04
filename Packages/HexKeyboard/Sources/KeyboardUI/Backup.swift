import Foundation

/// Sends iikb's files to the backup server built in as `Resources/Keys/backup.key` (its address on the first line, its
/// token on the second; docs/backup.md) each time they change, so they outlive a crash, a delete, an install of any kind,
/// a lost iPhone, and a bug that saves over them: the server keeps every version and deletes nothing.
/// It sends each file the server lacks or holds at another size or modification time to the second, as rsync's quick
/// check does, so a send that failed goes with the next one.
nonisolated public enum Backup {
    /// A folder and the name it has on the server, the same as `scripts/backup` gives it.
    public typealias Folder = (name: String, url: URL)

    public enum Outcome: Sendable {
        case upToDate, unreachable
    }

    private static let server: (url: URL, token: String)? = {
        guard let key = Bundle.module.url(forResource: "backup", withExtension: "key", subdirectory: "Keys"),
              let lines = try? String(contentsOf: key, encoding: .utf8).split(whereSeparator: \.isNewline), lines.count == 2,
              let url = URL(string: String(lines[0]))
        else { return nil }
        return (url, String(lines[1]))
    }()

    public static var isBuiltIn: Bool { server != nil }

    private static var library: URL { .libraryDirectory }

    /// What the keyboard learned, its emoji and GIF picks, its copy of the clipboard, and its settings.
    public static var keyboard: [Folder] {
        [("keyboard/support", .applicationSupportDirectory), ("keyboard/Preferences", library.appending(path: "Preferences"))]
    }

    /// Transcripts and their recordings, the Dictionary, and the app's settings.
    public static var app: [Folder] {
        [("app", .applicationSupportDirectory), ("app/Preferences", library.appending(path: "Preferences"))]
    }

    /// The clipboard history, the taps the keyboard shares, and the settings both sides read.
    public static var group: [Folder] {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SettingsStore.appGroup).map { [("group/Library", $0.appending(path: "Library"))] } ?? []
    }

    /// Parakeet's models, which download again, and what iOS may clear.
    private static let skipped: Set<String> = ["FluidAudio", "Caches"]

    /// Sends what changed in the background, letting the app or keyboard finish even as it goes away. `skip` names files
    /// not to send yet, by their name on the server.
    public static func sync(_ folders: [Folder], skip: @escaping @Sendable (String) -> Bool = { _ in false }) {
        guard isBuiltIn else { return }
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Backing up iikb") { expired in
            guard !expired else { return }
            let done = DispatchSemaphore(value: 0)
            Task {
                await send(folders, skip: skip)
                done.signal()
            }
            done.wait()
        }
    }

    /// Sends what changed and says how it went, or nil when the build has no backup server.
    @discardableResult
    public static func send(_ folders: [Folder], skip: @Sendable (String) -> Bool = { _ in false }) async -> Outcome? {
        guard let server else { return nil }
        var request = URLRequest(url: server.url)
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let held = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return .unreachable }
        let files = folders.flatMap(contents).filter { !skip($0.name) }
        for file in files where held[file.name] != [file.size, file.modified] {
            var put = request
            put.url = server.url.appending(path: file.name)
            put.httpMethod = "PUT"
            put.setValue(String(file.modified), forHTTPHeaderField: "X-Modified")
            guard let (_, response) = try? await URLSession.shared.upload(for: put, fromFile: file.url),
                  (response as? HTTPURLResponse)?.statusCode == 204
            else { return .unreachable }
        }
        return .upToDate
    }

    private static func contents(of folder: Folder) -> [(name: String, url: URL, size: Int, modified: Int)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let root = folder.url.resolvingSymlinksInPath().pathComponents
        guard let walk = FileManager.default.enumerator(at: folder.url, includingPropertiesForKeys: Array(keys)) else { return [] }
        var files: [(name: String, url: URL, size: Int, modified: Int)] = []
        for case let url as URL in walk {
            if skipped.contains(url.lastPathComponent) {
                walk.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate
            else { continue }
            let path = url.resolvingSymlinksInPath().pathComponents.dropFirst(root.count)
            files.append((([folder.name] + path).joined(separator: "/"), url, size, Int(modified.timeIntervalSince1970)))
        }
        return files
    }
}
