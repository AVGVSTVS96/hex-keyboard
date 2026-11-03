import AVFoundation
import CoreML
import FluidAudio
import UIKit

/// `-HexVoiceProbe <ultra|v3> [-HexVoiceProbeUnits ane|cpu|gpu]` (`scripts/voiceprobe`): times each of a Parakeet's
/// parts loading on this iPhone, then writes `Documents/probe.wav` three times, as it is and as dictation does
/// (`ParakeetTranscription`), logging to `Documents/probe.log`.
nonisolated enum VoiceProbe {
    static var asked: Bool { UserDefaults.standard.string(forKey: "HexVoiceProbe") != nil }

    @MainActor static func runIfAsked() {
        guard let name = UserDefaults.standard.string(forKey: "HexVoiceProbe") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        try? keepRunning()
        Task.detached {
            do { try await run(name) } catch { say("failed: \(error)") }
            say("done")
            exit(0)
        }
    }

    private static let engine = AVAudioEngine()

    /// Plays silence, so iOS doesn't suspend Hex when the probe launched it behind another app or a locked screen.
    @MainActor private static func keepRunning() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try AVAudioSession.sharedInstance().setActive(true)
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        silence.frameLength = 44_100
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.scheduleBuffer(silence, at: nil, options: .loops)
        player.play()
    }

    private static let log = URL.documentsDirectory.appendingPathComponent("probe.log")

    private static func say(_ line: String) {
        let line = "[probe \(Date.now.formatted(date: .omitted, time: .standard))] \(line) · thermal \(ProcessInfo.processInfo.thermalState.rawValue)\n"
        print(line, terminator: "")
        guard let file = try? FileHandle(forWritingTo: log) else {
            try? Data(line.utf8).write(to: log)
            return
        }
        file.seekToEndOfFile()
        file.write(Data(line.utf8))
        try? file.close()
    }

    private static func run(_ name: String) async throws {
        guard let version = VoiceModel.Model(rawValue: name)?.version else { return say("no Parakeet named \(name)") }
        let units: MLComputeUnits = switch UserDefaults.standard.string(forKey: "HexVoiceProbeUnits") {
        case "cpu": .cpuOnly
        case "gpu": .cpuAndGPU
        default: .cpuAndNeuralEngine
        }
        say("\(name), encoder on \(units.rawValue)")
        var began = Date.now
        let folder = try await AsrModels.download(version: version)
        say("files there after \(seconds(since: began))")
        let parts = [(ModelNames.ASR.preprocessorFile, MLComputeUnits.cpuOnly), (ModelNames.ASR.decoderFile, .cpuAndNeuralEngine), (ModelNames.ASR.jointV3File, .cpuAndNeuralEngine), (ModelNames.ASR.encoderFile, units)]
        for (file, unit) in parts {
            let config = MLModelConfiguration()
            config.computeUnits = unit
            began = .now
            _ = try await MLModel.load(contentsOf: folder.appendingPathComponent(file), configuration: config)
            say("\(file) loaded in \(seconds(since: began))")
        }
        began = .now
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let models = try AsrModels.loadLocal(from: folder, version: version, configuration: config, encoderComputeUnits: units)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        say("all loaded again in \(seconds(since: began))")
        let clip = URL.documentsDirectory.appendingPathComponent("probe.wav")
        let samples = try AudioConverter().resampleAudioFile(clip)
        let dictation = ParakeetTranscription(Task { manager }, model: name)
        for _ in 0..<3 {
            began = .now
            var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
            let text = try await manager.transcribe(samples, decoderState: &state).text
            say("wrote \(Double(samples.count) / 16_000)s as is in \(seconds(since: began)): \(text)")
            began = .now
            let written = try await dictation.text(of: samples)
            say("wrote it as dictation does in \(seconds(since: began)): \(written)")
        }
    }

    private static func seconds(since date: Date) -> String {
        Date.now.timeIntervalSince(date).formatted(.number.precision(.fractionLength(2))) + "s"
    }
}
