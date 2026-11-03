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
            Box(footer: kept ? "iikb keeps the sound of each dictation on this iPhone, so it can be written again with \(VoiceModel.shared.model.title)." : nil) {
                if let mic = transcript.mic { Fact(title: "Microphone", value: mic) }
                if kept {
                    ActionRow(title: writing ? VoiceModel.shared.state == .ready ? "Transcribing Again…" : "Transcribing Again once \(VoiceModel.shared.model.title) is ready…" : "Transcribe Again", symbol: "arrow.clockwise") { Task { await write() } }
                        .disabled(writing)
                }
                if let again {
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
