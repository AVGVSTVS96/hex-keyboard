import AVFoundation
import KeyboardUI
import Speech
import UIKit

/// The microphone and the transcriber behind the keyboard's voice typing. It transcribes on the iPhone as you speak
/// (Apple's SpeechTranscriber, the iOS 26 model, not the older one behind the system's dictation key), so when you're
/// done only the last words are left to finish.
@MainActor final class Listener {
    static let shared = Listener()

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var heard: Task<String, any Error>?
    private var tokens: [Int32] = []
    private(set) var state = Dictation.State.idle
    var onChange: (() -> Void)?
    var onLevel: ((Float) -> Void)?

    private init() {
        tokens = [
            Dictation.observe(.finish) { Task { await Listener.shared.finish() } },
            Dictation.observe(.cancel) { Task { await Listener.shared.cancel() } },
        ]
    }

    func start() async {
        guard state == .idle else { return }
        set(.listening)
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphone }
            let (module, heard) = try await Self.transcriber()
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Failure.language }
            let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
            self.input = input
            self.heard = heard
            try listen(into: input, as: format)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
            let analyzer = SpeechAnalyzer(modules: [module])
            self.analyzer = analyzer
            try await analyzer.start(inputSequence: stream)
            switch state {
            case .transcribing: await deliver(analyzer)
            case .idle: await analyzer.cancelAndFinishNow()
            case .listening: break
            }
        } catch {
            stopListening()
            await analyzer?.cancelAndFinishNow()
            set(.idle, failure: (error as? Failure)?.description ?? error.localizedDescription)
        }
    }

    /// Stops listening and hands the keyboard everything heard, once the transcriber is up if it isn't yet.
    func finish() async {
        guard state == .listening else { return }
        stopListening()
        set(.transcribing)
        input?.finish()
        if let analyzer { await deliver(analyzer) }
    }

    private func deliver(_ analyzer: SpeechAnalyzer) async {
        let background = UIApplication.shared.beginBackgroundTask()
        defer { UIApplication.shared.endBackgroundTask(background) }
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await heard?.value ?? ""
            set(.idle, heard: text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            set(.idle, failure: error.localizedDescription)
        }
        reset()
    }

    func cancel() async {
        guard state != .idle else { return }
        stopListening()
        input?.finish()
        await analyzer?.cancelAndFinishNow()
        heard?.cancel()
        reset()
        set(.idle)
    }

    private func reset() {
        analyzer = nil
        input = nil
        heard = nil
    }

    private func set(_ state: Dictation.State, heard: String? = nil, failure: String? = nil) {
        self.state = state
        Dictation.publish(Dictation.Status(state: state, heard: heard.flatMap { $0.isEmpty ? nil : $0 }, failure: failure))
        onChange?()
    }

    /// Mixes with whatever else is playing, so music keeps going while you talk.
    private func listen(into input: AsyncStream<AnalyzerInput>.Continuation, as format: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        let node = engine.inputNode
        let natural = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: natural, to: format) else { throw Failure.language }
        node.installTap(onBus: 0, bufferSize: 4096, format: natural, block: Self.tap(converter: converter, format: format, input: input) { level in
            Task { @MainActor in Listener.shared.onLevel?(level) }
        })
        engine.prepare()
        try engine.start()
    }

    private func stopListening() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Runs on the audio thread: converts each buffer to the transcriber's format and reports how loud it was.
    nonisolated private static func tap(converter: AVAudioConverter, format: AVAudioFormat, input: AsyncStream<AnalyzerInput>.Continuation, level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var fed = false
            converter.convert(to: converted, error: nil) { _, status in
                status.pointee = fed ? .noDataNow : .haveData
                defer { fed = true }
                return fed ? nil : buffer
            }
            input.yield(AnalyzerInput(buffer: converted))
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for index in 0 ..< frames { sum += samples[index] * samples[index] }
                level((sum / Float(frames)).squareRoot())
            }
        }
    }

    /// The newer SpeechTranscriber where the iPhone has it, else the dictation model with punctuation.
    private static func transcriber() async throws -> (any SpeechModule, Task<String, any Error>) {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return (module, Task {
                var text = ""
                for try await result in module.results where result.isFinal { text += String(result.text.characters) }
                return text
            })
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else { throw Failure.language }
        let module = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [], attributeOptions: [])
        return (module, Task {
            var text = ""
            for try await result in module.results where result.isFinal { text += String(result.text.characters) }
            return text
        })
    }

    private enum Failure: Error, CustomStringConvertible {
        case microphone, language

        var description: String {
            switch self {
            case .microphone: "Hex needs the microphone. Turn it on in Settings › Apps › Hex."
            case .language: "Voice typing doesn't support this iPhone's language yet."
            }
        }
    }
}
