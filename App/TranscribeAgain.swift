import SwiftUI

/// The microphone a transcript was said into, and, when Hex kept its sound, writing it again with the voice model picked
/// now, to keep or not.
struct RecordingSection: View {
    let transcript: Transcript
    @State private var again: VoiceModel.Written?
    @State private var writing = false
    @State private var failure: String?

    var body: some View {
        let kept = Transcripts.shared.hasRecording(transcript.id)
        if kept || transcript.mic != nil {
            Box(footer: kept ? "iikb keeps the sound of each dictation on this iPhone, so it can be shared as a voice memo or written again with \(VoiceModel.shared.model.title)." : nil) {
                if let mic = transcript.mic { Fact(title: "Microphone", value: mic) }
                if kept {
                    ShareLink(item: Memo(transcript), preview: SharePreview("Recording")) {
                        HStack {
                            Text("Share Recording")
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.blue)
                        .row()
                    }
                    .buttonStyle(.plain)
                    ActionRow(title: writing ? VoiceModel.shared.state == .ready ? "Transcribing Again…" : "Transcribing Again once \(VoiceModel.shared.model.title) is ready…" : "Transcribe Again", symbol: "arrow.clockwise") { Task { await write() } }
                        .disabled(writing)
                }
                if let again, again.text.isEmpty {
                    RowText(title: "Nothing heard", detail: "Written by \(again.model)").row()
                } else if let again {
                    RowText(title: again.text, detail: "Written by \(again.model)")
                        .textSelection(.enabled)
                        .row()
                    ActionRow(title: "Use This Transcript") {
                        Transcripts.shared.replace(transcript.id, with: again.text, heard: again.heard, model: again.model)
                        self.again = nil
                    }
                    ActionRow(title: "Copy", symbol: "doc.on.doc") { UIPasteboard.general.string = again.text }
                }
                if let failure { Text(failure).foregroundStyle(.red).row() }
            }
        }
    }

    private func write() async {
        writing = true
        failure = nil
        defer { writing = false }
        do {
            again = try await VoiceModel.shared.write(try Recording.read(Transcripts.shared.recording(of: transcript.id)))
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A transcript's recording to share as a voice memo, named for its first words.
nonisolated struct Memo: Transferable {
    let recording: URL
    let name: String

    @MainActor init(_ transcript: Transcript) {
        recording = Transcripts.shared.recording(of: transcript.id)
        let words = transcript.text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ").filter { !"/:".contains($0) }
        name = words.isEmpty ? "iikb Recording" : words
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Audio) { SentTransferredFile(try Recording.memo($0.recording, named: $0.name)) }
    }
}
