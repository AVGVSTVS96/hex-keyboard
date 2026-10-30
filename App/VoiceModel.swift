import AVFoundation
import FluidAudio
import Observation
import Speech

/// The speech model voice typing writes with: NVIDIA's Parakeet (moondream's post-training of v3, run on the Neural
/// Engine by FluidAudio), downloaded from Hugging Face the first time Hex opens and kept in the app's container. Until
/// it's on the iPhone, or if it can't be, Apple's SpeechTranscriber writes instead. Either way the sound never leaves
/// the iPhone.
@Observable final class VoiceModel {
    static let shared = VoiceModel()

    enum State: Equatable {
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private(set) var state = State.loading
    @ObservationIgnored private var parakeet: Task<AsrManager, any Error>?
    @ObservationIgnored private var downloading = false

    private static let version = AsrModelVersion.ultra

    private init() {}

    /// Downloads Parakeet if it isn't on the iPhone yet, then loads it, unless it's loaded, on its way, or failed since
    /// Hex launched. The first load compiles it for the Neural Engine.
    func prepare() {
        if case .failed = state { return }
        guard parakeet == nil, !downloading else { return }
        let folder = AsrModels.defaultCacheDirectory(for: Self.version)
        if AsrModels.modelsExist(at: folder, version: Self.version) { return load(folder) }
        downloading = true
        Task {
            defer { downloading = false }
            do {
                load(try await AsrModels.download(version: Self.version) { progress in
                    guard case .downloading = progress.phase else { return }
                    Task { @MainActor in VoiceModel.shared.state = .downloading(progress.fractionCompleted) }
                })
            } catch {
                failed(error)
            }
        }
    }

    private func load(_ folder: URL) {
        state = .loading
        let began = Date.now
        let parakeet = Task {
            let manager = AsrManager(config: .default)
            try await manager.loadModels(try await AsrModels.load(from: folder, version: Self.version))
            return manager
        }
        self.parakeet = parakeet
        Task {
            do {
                _ = try await parakeet.value
                state = .ready
                HostApp.log.notice("Parakeet ready after \(Date.now.timeIntervalSince(began), format: .fixed(precision: 1))s")
            } catch {
                self.parakeet = nil
                failed(error)
            }
        }
    }

    private func failed(_ error: any Error) {
        state = .failed(error.localizedDescription)
        HostApp.log.error("Parakeet failed: \(error.localizedDescription, privacy: .public)")
    }

    /// A new dictation's transcription: Parakeet's once it's on the iPhone, even while it loads, since it only writes
    /// once you stop talking.
    func transcription() async throws -> any Transcription {
        prepare()
        if let parakeet { return ParakeetTranscription(parakeet) }
        return try await SpeechTranscription.make()
    }
}

/// One dictation, from the microphone's sound to text.
nonisolated protocol Transcription: AnyObject, Sendable {
    /// For the log.
    var model: String { get }
    /// The sound it takes, which the microphone's is converted to.
    var format: AVAudioFormat { get }
    /// Runs on the audio thread.
    func hear(_ buffer: AVAudioPCMBuffer)
    /// Everything said, once no more sound is coming.
    func text() async throws -> String
    func cancel() async
}

/// Keeps the sound while you talk and writes it all down when you're done: Parakeet takes a whole recording at once,
/// fast enough on the Neural Engine that a minute of talking is written in well under a second.
nonisolated final class ParakeetTranscription: Transcription, @unchecked Sendable {
    let model = "Parakeet"
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let parakeet: Task<AsrManager, any Error>
    private let lock = NSLock()
    private var samples: [Float] = []

    init(_ parakeet: Task<AsrManager, any Error>) {
        self.parakeet = parakeet
    }

    func hear(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        lock.withLock { samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))) }
    }

    /// Pads a tap with next to nothing said up to the shortest sound Parakeet takes.
    func text() async throws -> String {
        var samples = lock.withLock { self.samples }
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: Int(format.sampleRate))
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        let parakeet = try await parakeet.value
        var state = TdtDecoderState.make(decoderLayers: await parakeet.decoderLayerCount)
        return try await parakeet.transcribe(samples, decoderState: &state).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {}
}

/// Apple's SpeechTranscriber (the iOS 26 model, not the older one behind the system's dictation key), else the dictation
/// model with punctuation. It writes as you speak, so when you're done only the last words are left to finish.
nonisolated final class SpeechTranscription: Transcription {
    let model = "SpeechTranscriber"
    let format: AVAudioFormat
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

    func text() async throws -> String {
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
