import Foundation
import KeyboardStore
import Observation
import UIKit

struct Transcript: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var seconds: Double
    /// False when it wasn't typed where you said it: you canceled it, or iikb ended mid-dictation.
    var typed: Bool
    /// Written down after iikb ended mid-dictation (an install, a crash, a dead iPhone), the next time it started.
    var recovered: Bool?
    /// The speech model that wrote it; nil before iikb kept it.
    var model: String?
    /// The microphone it was said into, as iOS names it; nil before iikb kept it.
    var mic: String?
    /// Whether that microphone was heard through Apple's voice processing, as a call is; nil before iikb kept it.
    var voiceProcessing: Bool?
    /// The way the iPhone's microphones heard it while they were compared (`Capture`), nil otherwise.
    var capture: String?
    /// The room and the speech in its recording as heard, before it was leveled, in dBFS (`Recording.levels`).
    var room: Double?
    var speech: Double?
    /// What the model wrote, when your style or `Vocabulary` changed it.
    var heard: String?
    /// The bundle ID of the app it was said for; nil when the keyboard couldn't tell, or before iikb kept it.
    var app: String?
    /// What the keyboard typed for it and what that became once its field was sent or left, every edit in it included;
    /// nil until then, when it wasn't typed, or before iikb kept it.
    var field: Field?
    /// What it was first written as, kept once another writing is put in its place; nil while none has been.
    var replaced: Replaced?

    struct Replaced: Codable, Hashable {
        var model: String?
        var text: String
    }

    struct Field: Codable, Hashable {
        var typed: String
        var final: String
        /// The field was emptied after it, as sending a message does; false when it was left.
        var sent: Bool
        /// The keyboard lost its place in the field while something there changed, so `final` may be wrong.
        var uncertain: Bool?
        /// The field's keyboard (`InputKind`) and content type (`InputContent`, when it says one), and the text the
        /// keyboard saw before the caret there, so scripts/voiceloop replays it in the same field; nil before iikb kept them.
        var kind: String?
        var content: String?
        var before: String?
    }

    var words: Int { text.split(whereSeparator: \.isWhitespace).count }

    /// The text, or, when the model wrote nothing, what it heard that your editing left out, else that it heard nothing.
    var shown: String { text.isEmpty ? heard.map { "Left out: \($0)" } ?? "Nothing heard" : text }
}

/// Every dictation the app transcribed, newest first, in one JSON line each in the app's own container, and the sound of
/// each as a `Recording` beside it, written as it's heard, up to 512 MB (about 4½ hours of talking), past which the oldest
/// lose their sound. A recording with no transcript, left by an app that ended mid-dictation, is written down the next
/// time the app starts, and the keyboard says so. Nothing leaves the iPhone but for the backup server a build may have
/// (`Backup`): the keyboard reads only the texts, from the copy `share` writes, and the app's only download is the voice model.
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

    /// False while the file is there but can't be read, as before the iPhone's first unlock when iOS starts the app in
    /// the background: `all` then holds only what was added since, and nothing writes the file whole until it's read.
    @ObservationIgnored private var loaded = false

    private init() {
        load()
        _ = Dictation.observe(.edited) { Transcripts.shared.takeEdits() }
        DispatchQueue.main.async { Transcripts.shared.takeEdits() }
        _ = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Transcripts.shared.takeEdits() }
        }
        guard loaded else { return }
        share()
        let ids = Set(all.map(\.id)).union(unread.compactMap { try? JSONDecoder().decode(Named.self, from: $0).id })
        unwritten = ((try? FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? []).filter { file in
            UUID(uuidString: file.deletingPathExtension().lastPathComponent).map { !ids.contains($0) } ?? false
        }
    }

    /// Reads the file once it can be, keeping what was added before then. Whether it's read, or there's none.
    @discardableResult private func load() -> Bool {
        guard !loaded else { return true }
        guard let data = try? Data(contentsOf: url) else { // file: transcripts.jsonl, read whole once it can be; until then `save` leaves it alone
            loaded = !FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            return loaded
        }
        let decoder = JSONDecoder()
        var unread: [Data] = []
        let read = data.split(separator: UInt8(ascii: "\n")).compactMap { (line) -> Transcript? in
            if let transcript = try? decoder.decode(Transcript.self, from: line) { return transcript }
            unread.append(Data(line))
            return nil
        }
        let added = Set(all.map(\.id))
        all = (all + read.filter { !added.contains($0.id) }).sorted { $0.date > $1.date }
        self.unread = unread
        loaded = true
        return true
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
                let written = try await VoiceModel.shared.write(samples, for: nil)
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
    /// A level in dBFS, to a tenth.
    private static func decibels(_ level: Float) -> Double {
        (Double(20 * log10(max(level, 1e-6))) * 10).rounded() / 10
    }

    /// out), and the sound is the only copy, to write again.
    func add(_ text: String, heard: String, id: Transcript.ID, at date: Date, seconds: Double, typed: Bool, model: String, mic: String?, voiceProcessing: Bool? = nil, capture: Capture? = nil, levels: (room: Float, speech: Float)? = nil, app: String? = nil, recovered: Bool = false) {
        let transcript = Transcript(
            id: id, date: date, text: text, seconds: seconds, typed: typed, recovered: recovered ? true : nil, model: model, mic: mic, voiceProcessing: voiceProcessing,
            capture: capture?.rawValue, room: levels.map { Self.decibels($0.room) }, speech: levels.map { Self.decibels($0.speech) },
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
        guard load() else { return }
        let waiting = Set(unread.compactMap { try? JSONDecoder().decode(Named.self, from: $0).id.uuidString })
        var taken: [URL] = []
        for (file, edit) in Dictation.edits {
            if let index = all.firstIndex(where: { $0.id.uuidString == edit.id }) {
                all[index].field = Transcript.Field(typed: edit.typed, final: edit.final, sent: edit.sent, uncertain: edit.uncertain ? true : nil,
                                                     kind: edit.kind?.rawValue, content: edit.content?.rawValue, before: edit.before)
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
        load()
        unread = []
        delete(Set(all.map(\.id)))
    }

    /// Puts a new writing of a transcript's recording in its place.
    func replace(_ id: Transcript.ID, with text: String, heard: String, model: String) {
        guard let index = all.firstIndex(where: { $0.id == id }), !text.isEmpty else { return }
        all[index].replaced = all[index].replaced ?? Transcript.Replaced(model: all[index].model, text: all[index].text)
        all[index].text = text
        all[index].heard = heard == text ? nil : heard
        all[index].model = model
        save()
    }

    /// Writes again with the picked Parakeet each dictation Apple's model wrote while a Parakeet got ready, as builds
    /// before 4d500d1 (Nov 3) did, one at a time while nothing is being recorded or written; `replace` keeps Apple's
    /// words. What a dictation interrupts waits for the next launch.
    func rewriteApple() async {
        guard VoiceModel.shared.model != .apple else { return }
        for transcript in all where transcript.model?.hasPrefix("Apple, while") == true && hasRecording(transcript.id) {
            guard !Listener.shared.isListening, !Listener.shared.isWriting else { return }
            guard let written = try? await VoiceModel.shared.write(Recording.read(recording(of: transcript.id)), for: transcript.app), written.model != VoiceModel.Model.apple.title else { continue }
            replace(transcript.id, with: written.text, heard: written.heard, model: written.model)
        }
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

    /// Writes the file whole, only once it's read, or set aside when the iPhone is unlocked and it still can't be.
    private func save() {
        guard load() || setAside() else { return }
        let encoder = JSONEncoder()
        let kept = unread.map { $0 + [UInt8(ascii: "\n")] }
        let lines = kept + all.reversed().compactMap { try? encoder.encode($0) + [UInt8(ascii: "\n")] }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(lines.joined()).write(to: url, options: .atomic) // file: transcripts.jsonl rewritten whole, only once read or set aside
        Backup.syncApp()
        share()
    }

    /// The keyboard's copy, for its Transcripts panel, written in order off the main thread.
    private func share() {
        let entries = all.filter { !$0.text.isEmpty }.map { TranscriptFeed.Entry(id: $0.id.uuidString, date: $0.date.timeIntervalSince1970, text: $0.text) }
        Self.sharing.async { TranscriptFeed.share(entries) }
    }

    private static let sharing = DispatchQueue(label: "com.shahidy.iikb.transcripts", qos: .utility)

    /// Moves a file that can't be read though nothing locks it to `transcripts-unread-<seconds>.jsonl`, as `StoredFile`
    /// does, so the backup still sends it. Whether the file can now be written.
    private func setAside() -> Bool {
        guard UIApplication.shared.isProtectedDataAvailable else { return false }
        let aside = url.deletingLastPathComponent().appending(path: "transcripts-unread-\(Int(Date.now.timeIntervalSince1970)).jsonl")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            HostApp.log.fault("transcripts.jsonl can't be read or set aside: \(error.localizedDescription, privacy: .public)")
            return false
        }
        HostApp.log.fault("transcripts.jsonl couldn't be read; set aside as \(aside.lastPathComponent, privacy: .public)")
        loaded = true
        return true
    }
}
