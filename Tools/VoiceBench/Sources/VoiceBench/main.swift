import FluidAudio
import Foundation

/// `VoiceBench <corpus> <way> [percent loudness]`: writes every clip in `<corpus>/clips.jsonl` at the given loudness
/// into `<corpus>/outputs/<way>-<percent>.jsonl`, with the milliseconds each took, in one way:
/// - `asis`: Parakeet v3 as FluidAudio does by itself;
/// - `dictation`: as iikb's dictation does (`Parakeet.dictate`, the app's own file);
/// - `vocab`: dictation, then FluidAudio's CTC keyword spotter boosting the Dictionary (`<corpus>/vocabulary.json`) with
///   the thresholds 0.18.2 gives dictation (#967: no added boost, 0.7 similarity), since 0.18.0's session boosts every
///   term by 4.5 and so wrote one common word as a term 164 times in Bassim's dictations;
/// - `vqe`: LocalVQE's noise suppression, then dictation;
/// - `phonon2`, `bark3`: dictation with that model in place of v3.
/// Prints the peak memory the run took once its models were loaded and every clip written.
struct Clip: Decodable { let id: String; let audio_path: String }
struct Row: Encodable { let id, text: String; let ms: Int }
struct Vocabulary: Decodable { struct Term: Decodable { let term: String; let heardAs: [String] }; let terms: [Term] }

let arguments = CommandLine.arguments
let corpus = URL(fileURLWithPath: arguments[1])
let way = arguments[2]
let loudness = arguments.count > 3 ? Float(arguments[3])! : 100
let clips = try String(contentsOf: corpus.appending(path: "clips.jsonl"), encoding: .utf8)
    .split(separator: "\n").map { try JSONDecoder().decode(Clip.self, from: Data($0.utf8)) }
let manager = AsrManager(config: .default)
try await manager.loadModels(try await AsrModels.downloadAndLoad(version: way == "phonon2" ? .phonon2 : way == "bark3" ? .bark3 : .v3))
let vqe = way == "vqe" ? try await LocalVqeManager() : nil
var boost: (spotter: CtcKeywordSpotter, rescorer: VocabularyRescorer, vocabulary: CustomVocabularyContext)?
if way == "vocab" {
    let ctc = try await CtcModels.downloadAndLoad()
    let terms = try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: corpus.appending(path: "vocabulary.json")))
        .terms.map { CustomVocabularyTerm(text: $0.term, aliases: $0.heardAs.isEmpty ? nil : $0.heardAs) }
    let vocabulary = try await VocabularyBoostingSession(vocabulary: CustomVocabularyContext(terms: terms), ctcModels: ctc).vocabulary
    let spotter = CtcKeywordSpotter(models: ctc, blankId: ctc.vocabulary.count)
    boost = (spotter, try await VocabularyRescorer.create(spotter: spotter, vocabulary: vocabulary, ctcModelDirectory: CtcModels.defaultCacheDirectory()), vocabulary)
}
let converter = AudioConverter()

func peak() -> Int {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return usage.ru_maxrss / 1_000_000
}

let loaded = peak()
var lines: [String] = []
for clip in clips {
    var samples = try converter.resampleAudioFile(corpus.appending(path: clip.audio_path)).map { $0 * loudness / 100 }
    let start = ContinuousClock.now
    let text: String
    switch way {
    case "asis":
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        text = try await manager.transcribe(samples, decoderState: &state, language: nil).text
    case "vocab":
        samples = Recording.leveled(samples)
        let shortest = ASRConstants.minimumRequiredSamples(forSampleRate: 16_000)
        if samples.count < shortest { samples += repeatElement(0, count: shortest - samples.count) }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state, language: .english)
        let spotted = try await boost!.spotter.spotKeywordsWithLogProbs(audioSamples: samples, customVocabulary: boost!.vocabulary)
        let boosted = boost!.rescorer.ctcTokenRescore(
            transcript: result.text, tokenTimings: result.tokenTimings ?? [], logProbs: spotted.logProbs,
            frameDuration: spotted.frameDuration, cbw: 0, minSimilarity: 0.7)
        text = (boosted.wasModified ? boosted.text : result.text).trimmingCharacters(in: .whitespacesAndNewlines)
    case "vqe":
        text = try await manager.dictate(try await vqe!.process(mic: samples))
    default:
        text = try await manager.dictate(samples)
    }
    let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
    lines.append(String(decoding: try JSONEncoder().encode(Row(id: clip.id, text: text, ms: ms)), as: UTF8.self))
}
let outputs = corpus.appending(path: "outputs")
try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
try (lines.joined(separator: "\n") + "\n").write(to: outputs.appending(path: "\(way)-\(Int(loudness)).jsonl"), atomically: true, encoding: .utf8)
print("\(way)-\(Int(loudness)): \(clips.count) clips, peak memory \(loaded) MB loaded, \(peak()) MB after")
