import FluidAudio
import Foundation

/// `VoiceBench <corpus> <asis|dictation> [percent loudness]`: writes every clip in `<corpus>/clips.jsonl` with Parakeet v3,
/// as FluidAudio does by itself or as iikb's dictation does (`Parakeet.dictate`, the app's own file), at the given
/// loudness, into `<corpus>/outputs/<way>-<percent>.jsonl`.
struct Clip: Decodable { let id: String; let audio_path: String }
struct Row: Encodable { let id, text: String }

let arguments = CommandLine.arguments
let corpus = URL(fileURLWithPath: arguments[1])
let dictation = arguments[2] == "dictation"
let loudness = arguments.count > 3 ? Float(arguments[3])! : 100
let clips = try String(contentsOf: corpus.appending(path: "clips.jsonl"), encoding: .utf8)
    .split(separator: "\n").map { try JSONDecoder().decode(Clip.self, from: Data($0.utf8)) }
let manager = AsrManager(config: .default)
try await manager.loadModels(try await AsrModels.downloadAndLoad(version: .v3))
let converter = AudioConverter()

var lines: [String] = []
for clip in clips {
    var samples = try converter.resampleAudioFile(corpus.appending(path: clip.audio_path)).map { $0 * loudness / 100 }
    let text: String
    if dictation {
        text = try await manager.dictate(samples)
    } else {
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        text = try await manager.transcribe(samples, decoderState: &state, language: nil).text
    }
    lines.append(String(decoding: try JSONEncoder().encode(Row(id: clip.id, text: text)), as: UTF8.self))
}
let outputs = corpus.appending(path: "outputs")
try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
try (lines.joined(separator: "\n") + "\n").write(to: outputs.appending(path: "\(arguments[2])-\(Int(loudness)).jsonl"), atomically: true, encoding: .utf8)
