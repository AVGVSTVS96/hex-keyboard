import AVFoundation
import SwiftUI

extension VoiceModel {
    /// Writes a kept `Recording` down again, with the model picked now, or Apple's while it gets ready, and your
    /// vocabulary.
    func again(_ recording: [Float]) async throws -> (text: String, heard: String, model: String) {
        let transcription = try await transcription()
        if let format = transcription.format {
            guard let heard = Self.converted(recording, to: format) else { throw Unconvertible() }
            transcription.hear(heard)
        }
        let heard = try await transcription.text(of: recording)
        return (VoiceVocabulary.shared.vocabulary.corrected(heard), heard, transcription.model)
    }

    private static func converted(_ recording: [Float], to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: Recording.format, frameCapacity: AVAudioFrameCount(recording.count)),
              let converter = AVAudioConverter(from: Recording.format, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(recording.count) * format.sampleRate / 16_000) + 1)
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        recording.withUnsafeBufferPointer { buffer.floatChannelData?[0].update(from: $0.baseAddress!, count: recording.count) }
        nonisolated(unsafe) var fed = false
        converter.convert(to: converted, error: nil) { _, status in
            status.pointee = fed ? .endOfStream : .haveData
            defer { fed = true }
            return fed ? nil : buffer
        }
        return converted
    }

    private struct Unconvertible: LocalizedError {
        var errorDescription: String? { "This recording can't be read by Apple's model." }
    }
}

/// The microphone a transcript was said into, and, when Hex kept its sound, writing it again with the voice model picked
/// now, to keep or not.
struct RecordingSection: View {
    let transcript: Transcript
    @State private var again: (text: String, heard: String, model: String)?
    @State private var writing = false
    @State private var failure: String?

    var body: some View {
        let kept = Transcripts.shared.hasRecording(transcript.id)
        if kept || transcript.mic != nil {
            Section {
                if let mic = transcript.mic { LabeledContent("Microphone", value: mic) }
                if kept {
                    Button(writing ? "Transcribing Again…" : "Transcribe Again") { Task { await write() } }
                        .disabled(writing)
                }
                if let again {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(again.text)
                            .textSelection(.enabled)
                        Text("Written by \(again.model)")
                            .font(.footnote)
                            .foregroundStyle(Color.hexSecondary)
                    }
                    .padding(.vertical, 4)
                    Button("Use This Transcript") {
                        Transcripts.shared.replace(transcript.id, with: again.text, heard: again.heard, model: again.model)
                        self.again = nil
                    }
                    Button("Copy") { UIPasteboard.general.string = again.text }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            } footer: {
                if kept { Text("Hex keeps the sound of each dictation on this iPhone, so it can be written again with \(VoiceModel.shared.model.title).") }
            }
            .listRowBackground(Color.hexCard)
        }
    }

    private func write() async {
        writing = true
        failure = nil
        defer { writing = false }
        do {
            again = try await VoiceModel.shared.again(try Recording.read(Transcripts.shared.recording(of: transcript.id)))
        } catch {
            failure = error.localizedDescription
        }
    }
}
