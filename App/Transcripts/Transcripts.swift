import Foundation
import HexStore
import Observation

struct Transcript: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var seconds: Double
    /// False when it wasn't typed where you said it: you canceled it, or Hex ended mid-dictation.
    var typed: Bool
    /// Written down after Hex ended mid-dictation (an install, a crash, a dead iPhone), the next time it started.
    var recovered: Bool?
    /// The speech model that wrote it; nil before Hex kept it.
    var model: String?
    /// The microphone it was said into, as iOS names it; nil before Hex kept it.
    var mic: String?
    /// Whether that microphone was heard through Apple's voice processing, as a call is; nil before Hex kept it.
    var voiceProcessing: Bool?
    /// What the model wrote, when your style or `Vocabulary` changed it.
    var heard: String?
    /// The bundle ID of the app it was said for; nil when the keyboard couldn't tell, or before Hex kept it.
    var app: String?
    /// What the keyboard typed for it and what that became once its field was sent or left, every edit in it included;
    /// nil until then, when it wasn't typed, or before Hex kept it.
    var field: Field?

    struct Field: Codable, Hashable {
        var typed: String
        var final: String
        /// The field was emptied after it, as sending a message does; false when it was left.
        var sent: Bool
        /// The keyboard lost its place in the field while something there changed, so `final` may be wrong.
        var uncertain: Bool?
    }

    var words: Int { text.split(whereSeparator: \.isWhitespace).count }

    /// The text, or, when the model wrote nothing, what it heard that your editing left out, else that it heard nothing.
    var shown: String { text.isEmpty ? heard.map { "Left out: \($0)" } ?? "Nothing heard" : text }
}

/// Every dictation the app transcribed, newest first, in one JSON line each in the app's own container, and the sound of
/// each as a `Recording` beside it, written as it's heard, up to 512 MB (about 4½ hours of talking), past which the oldest
/// lose their sound. A recording with no transcript, left by an app that ended mid-dictation, is written down the next
/// time the app starts, and the keyboard says so. Nothing leaves the iPhone but for the backup server a build may have
/// (`Backup`): the keyboard never reads it, and the app's only download is the voice model.
@Observable final class Transcripts {
    static let shared = Transcripts()

    private(set) var all: [Transcript] = []
    @ObservationIgnored private let url = URL.applicationSupportDirectory.appending(path: "transcripts.jsonl")
    @ObservationIgnored private let recordings = URL.applicationSupportDirectory.appending(path: "recordings")
    @ObservationIgnored private var unwritten: [URL] = []
    /// Lines this build can't read (cut short, or written by a build that keeps a transcript another way), written
    /// back as they were each time the file is, so a rewrite never drops them.
    @ObservationIgnored private var unread: [Data] = []

    private struct Named: Decodable {
        var id: UUID
    }

    private init() {
        if let data = try? Data(contentsOf: url) { // file: unlisted (transcripts.jsonl: a read that fails leaves the list empty, and the next save writes over the file)
            let decoder = JSONDecoder()
            var unread: [Data] = []
            all = data.split(separator: UInt8(ascii: "\n")).compactMap { (line) -> Transcript? in
                if let transcript = try? decoder.decode(Transcript.self, from: line) { return transcript }
                unread.append(Data(line))
                return nil
            }.sorted { $0.date > $1.date }
            self.unread = unread
        }
        _ = Dictation.observe(.edited) { Transcripts.shared.takeEdits() }
        DispatchQueue.main.async { Transcripts.shared.takeEdits() }
        let ids = Set(all.map(\.id)).union(unread.compactMap { try? JSONDecoder().decode(Named.self, from: $0).id })
        unwritten = ((try? FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? []).filter { file in
            UUID(uuidString: file.deletingPathExtension().lastPathComponent).map { !ids.contains($0) } ?? false
        }
    }

    /// Writes down the recordings an ended app left without a transcript, kept as not typed, and tells the keyboard.
    /// One that can't be written now waits for the next launch.
    func recover() async {
        for file in unwritten {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), let samples = try? Recording.read(file) else { continue }
            guard !samples.isEmpty else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            do {
                let written = try await VoiceModel.shared.write(samples)
                try? Recording.write(samples, to: file)
                add(written.text, heard: written.heard, id: id, at: date, seconds: Double(samples.count) / 16_000, typed: false, model: written.model, mic: nil, recovered: true)
                Dictation.leave(.notice("A dictation cut off when iikb closed is in iikb › Transcripts"))
            } catch {
                HostApp.log.error("couldn't write down \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        unwritten = []
    }

    /// Keeps a dictation whose `Recording` was written to `recording(of: id)` as it was heard, with its sound, even when
    /// the model wrote nothing: that's when it failed you (a low rumble, speech too quiet, or an "um" your editing left
    /// out), and the sound is the only copy, to write again.
    func add(_ text: String, heard: String, id: Transcript.ID, at date: Date, seconds: Double, typed: Bool, model: String, mic: String?, voiceProcessing: Bool? = nil, app: String? = nil, recovered: Bool = false) {
        let transcript = Transcript(
            id: id, date: date, text: text, seconds: seconds, typed: typed, recovered: recovered ? true : nil, model: model, mic: mic, voiceProcessing: voiceProcessing,
            heard: heard == text ? nil : heard, app: app
        )
        all.insert(transcript, at: all.firstIndex { $0.date < date } ?? all.endIndex)
        trim()
        guard let line = try? JSONEncoder().encode(transcript) else { return }
        do {
            let file = try FileHandle(forWritingTo: url) // file: append-only log (transcripts.jsonl)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: line + [UInt8(ascii: "\n")])
            Backup.syncApp()
        } catch {
            save()
        }
    }

    /// Keeps what the keyboard says each dictation became with its transcript, and only then lets go of what it said.
    /// What belongs to a line this build can't read waits for a build that can; what belongs to no transcript goes.
    func takeEdits() {
        let waiting = Set(unread.compactMap { try? JSONDecoder().decode(Named.self, from: $0).id.uuidString })
        var taken: [URL] = []
        for (file, edit) in Dictation.edits {
            if let index = all.firstIndex(where: { $0.id.uuidString == edit.id }) {
                all[index].field = Transcript.Field(typed: edit.typed, final: edit.final, sent: edit.sent, uncertain: edit.uncertain ? true : nil)
            } else if waiting.contains(edit.id) {
                continue
            }
            taken.append(file)
        }
        guard !taken.isEmpty else { return }
        save()
        for file in taken { _ = Dictation.take(file) }
    }

    func delete(_ ids: Set<Transcript.ID>) {
        all.removeAll { ids.contains($0.id) }
        save()
        for id in ids { try? FileManager.default.removeItem(at: recording(of: id)) }
    }

    /// Every transcript, the lines this build can't read included.
    func deleteAll() {
        unread = []
        delete(Set(all.map(\.id)))
    }

    /// Puts a new writing of a transcript's recording in its place.
    func replace(_ id: Transcript.ID, with text: String, heard: String, model: String) {
        guard let index = all.firstIndex(where: { $0.id == id }), !text.isEmpty else { return }
        all[index].text = text
        all[index].heard = heard == text ? nil : heard
        all[index].model = model
        save()
    }

    func recording(of id: Transcript.ID) -> URL {
        recordings.appending(path: "\(id.uuidString).wav")
    }

    func hasRecording(_ id: Transcript.ID) -> Bool {
        FileManager.default.fileExists(atPath: recording(of: id).path)
    }

    /// Oldest dictation first, by its transcript's date: a file's creation date is when it was last put on the iPhone,
    /// which for every recording `scripts/restore` puts back is the restore.
    private func trim() {
        let folder = recordings
        let said = Dictionary(all.map { ($0.id.uuidString, $0.date) }, uniquingKeysWith: { max($0, $1) })
        Task.detached(priority: .utility) {
            let files = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey]
            let kept = ((try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []).compactMap { url in
                (try? url.resourceValues(forKeys: Set(keys))).map { (url, $0.fileSize ?? 0, said[url.deletingPathExtension().lastPathComponent] ?? $0.creationDate ?? .distantPast) }
            }.sorted { $0.2 > $1.2 }
            var bytes = 0
            for (url, size, _) in kept {
                bytes += size
                if bytes > 512_000_000 { try? files.removeItem(at: url) }
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        let kept = unread.map { $0 + [UInt8(ascii: "\n")] }
        let lines = kept + all.reversed().compactMap { try? encoder.encode($0) + [UInt8(ascii: "\n")] }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(lines.joined()).write(to: url, options: .atomic) // file: unlisted (transcripts.jsonl rewritten whole, even over a file init couldn't read)
        Backup.syncApp()
    }
}
