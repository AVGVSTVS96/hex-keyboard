import AVFoundation
import FluidAudio
import Observation
import Speech

/// The speech model voice typing writes with, picked in Settings: one of NVIDIA's Parakeets, run on the Neural Engine by
/// FluidAudio and downloaded from Hugging Face once, or Apple's SpeechTranscriber. Until the Parakeet you picked is
/// loaded, Apple's writes, and the transcript says so. Either way the sound never leaves the iPhone.
@Observable final class VoiceModel {
    static let shared = VoiceModel()

    nonisolated enum Model: String, CaseIterable {
        case ultra, v3, apple

        var title: String {
            switch self {
            case .ultra: "Parakeet Ultra"
            case .v3: "Parakeet v3"
            case .apple: "Apple"
            }
        }

        var version: AsrModelVersion? {
            switch self {
            case .ultra: .ultra
            case .v3: .v3
            case .apple: nil
            }
        }
    }

    enum State: Equatable {
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private static let modelKey = "voiceModel"

    private(set) var model = UserDefaults.standard.string(forKey: modelKey).flatMap(Model.init) ?? .v3
    private(set) var state = State.loading
    @ObservationIgnored private var parakeet: Task<AsrManager, any Error>?
    @ObservationIgnored private var preparing: Task<Void, Never>?

    private init() {}

    /// Lets go of the model in use, so only one is ever in memory, and gets the new one ready.
    func pick(_ model: Model) {
        guard model != self.model else { return }
        UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
        self.model = model
        preparing?.cancel()
        preparing = nil
        parakeet = nil
        state = .loading
        prepare()
    }

    /// Downloads the picked Parakeet if it isn't on the iPhone yet, then loads it, unless it's loaded, on its way, or
    /// failed since it was picked. The first load compiles it for the Neural Engine; later ones read that from a cache.
    func prepare() {
        guard let version = model.version else { return state = .ready }
        if case .failed = state { return }
        guard parakeet == nil, preparing == nil else { return }
        let model = model
        preparing = Task {
            let began = Date.now
            do {
                let folder = try await AsrModels.download(version: version) { progress in
                    guard case .downloading = progress.phase else { return }
                    Task { @MainActor in
                        guard VoiceModel.shared.model == model else { return }
                        VoiceModel.shared.state = .downloading(progress.fractionCompleted)
                    }
                }
                guard self.model == model else { return }
                state = .loading
                let parakeet = Task.detached {
                    let manager = AsrManager(config: .default)
                    try await manager.loadModels(try await AsrModels.load(from: folder, version: version))
                    return manager
                }
                self.parakeet = parakeet
                _ = try await parakeet.value
                guard self.model == model else { return }
                state = .ready
                HostApp.log.notice("\(model.title, privacy: .public) ready after \(Date.now.timeIntervalSince(began), format: .fixed(precision: 1))s")
            } catch {
                guard self.model == model else { return }
                parakeet = nil
                state = .failed(error.localizedDescription)
                HostApp.log.error("\(model.title, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            preparing = nil
        }
    }

    /// A new dictation's transcription: the picked model's once it's loaded, else Apple's, named for the transcript as
    /// standing in.
    func transcription() async throws -> any Transcription {
        prepare()
        if state == .ready, let parakeet { return ParakeetTranscription(parakeet, model: model.title) }
        let apple = try await SpeechTranscription.make()
        if model != .apple { apple.model = "Apple, while \(model.title) loaded" }
        return apple
    }
}

/// One dictation, from the microphone's sound to text.
nonisolated protocol Transcription: AnyObject, Sendable {
    /// For the log and the transcript.
    var model: String { get }
    /// The sound it hears while you talk, which the microphone's is converted to; nil when it only reads the recording.
    var format: AVAudioFormat? { get }
    /// Runs on the audio thread.
    func hear(_ buffer: AVAudioPCMBuffer)
    /// Everything said, once no more sound is coming, given all of it as a `Recording`.
    func text(of recording: [Float]) async throws -> String
    func cancel() async
}

/// Writes the whole recording down when you're done: Parakeet takes it at once, fast enough on the Neural Engine that a
/// minute of talking is written in well under a second.
nonisolated final class ParakeetTranscription: Transcription, @unchecked Sendable {
    let model: String
    let format: AVAudioFormat? = nil
    private let parakeet: Task<AsrManager, any Error>

    init(_ parakeet: Task<AsrManager, any Error>, model: String) {
        self.parakeet = parakeet
        self.model = model
    }

    func hear(_ buffer: AVAudioPCMBuffer) {}

    /// Pads a tap with next to nothing said up to the shortest sound Parakeet takes. English keeps v3 to the Latin
    /// alphabet, which it otherwise leaves for Cyrillic on short or unclear English.
    func text(of recording: [Float]) async throws -> String {
        var samples = Recording.leveled(recording)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        let parakeet = try await parakeet.value
        var state = TdtDecoderState.make(decoderLayers: await parakeet.decoderLayerCount)
        return try await parakeet.transcribe(samples, decoderState: &state, language: .english).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {}
}

/// Apple's SpeechTranscriber (the iOS 26 model, not the older one behind the system's dictation key), else the dictation
/// model with punctuation. It writes as you speak, so when you're done only the last words are left to finish.
nonisolated final class SpeechTranscription: Transcription, @unchecked Sendable {
    var model = "Apple"
    let format: AVAudioFormat?
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let analyzer: Task<SpeechAnalyzer, any Error>
    private let heard: Task<String, any Error>

    static func make() async throws -> SpeechTranscription {
        let (module, heard) = try await transcriber()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw Unsupported() }
        return SpeechTranscription(module, format: format, heard: heard)
    }

    private init(_ module: any SpeechModule, format: AVAudioFormat, heard: Task<String, any Error>) {
        self.format = format
        self.heard = heard
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.input = input
        analyzer = Task {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
            let analyzer = SpeechAnalyzer(modules: [module])
            try await analyzer.start(inputSequence: stream)
            return analyzer
        }
    }

    func hear(_ buffer: AVAudioPCMBuffer) {
        input.yield(AnalyzerInput(buffer: buffer))
    }

    func text(of _: [Float]) async throws -> String {
        input.finish()
        try await analyzer.value.finalizeAndFinishThroughEndOfInput()
        return try await heard.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        input.finish()
        heard.cancel()
        await (try? analyzer.value)?.cancelAndFinishNow()
    }

    private static func transcriber() async throws -> (any SpeechModule, Task<String, any Error>) {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return (module, Task {
                var text = ""
                for try await result in module.results where result.isFinal { text += String(result.text.characters) }
                return text
            })
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else { throw Unsupported() }
        let module = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [], attributeOptions: [])
        return (module, Task {
            var text = ""
            for try await result in module.results where result.isFinal { text += String(result.text.characters) }
            return text
        })
    }

    private struct Unsupported: LocalizedError {
        var errorDescription: String? { "Voice typing doesn't support this iPhone's language yet." }
    }
}
