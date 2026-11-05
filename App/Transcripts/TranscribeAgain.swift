import SwiftUI

/// The microphone a transcript was said into and whether voice processing heard it, and, when iikb kept its sound,
/// writing it again with the voice model picked now, to keep or not.
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
                if let voiceProcessing = transcript.voiceProcessing { Fact(title: "Voice Processing", value: voiceProcessing ? "On" : "Off") }
                if let capture = transcript.capture.flatMap(Capture.init) { Fact(title: "Compared As", value: capture.title) }
                if kept {
                    ActionRow(title: "Share Recording", symbol: "square.and.arrow.up") { share() }
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

    private func share() {
        failure = nil
        let words = transcript.text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ").filter { !"/:".contains($0) }
        do {
            let memo = try Recording.memo(Transcripts.shared.recording(of: transcript.id), named: words.isEmpty ? "iikb Recording" : words)
            let sheet = UIActivityViewController(activityItems: [memo], applicationActivities: nil)
            sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: memo.deletingLastPathComponent()) }
            let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
            var top = window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            if let view = top?.view {
                sheet.popoverPresentationController?.sourceView = view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            top?.present(sheet, animated: true)
        } catch {
            failure = error.localizedDescription
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
