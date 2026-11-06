import Foundation
import KeyboardCore

/// `VoiceText <en.lexicon> <vocabulary.json> <typing-memory.json|-> <style> <editing> <lists> <auto-capitalization on|off>`: for each
/// `{id, heard, field?, before?}` line on stdin, what iikb types for what the voice model wrote (`heard`), as the iPhone
/// does it: the app's writing and Dictionary (`DictationWriting.typed` and `.plain` in App/Voice), then the keyboard's
/// reading of a field of that kind (`InputKind`'s name, text by default) after `before` (`TypingEngine`'s `.dictated`),
/// with the words the keyboard has seen typed (the keyboard's saved memory, as scripts/gate reads it).
/// Writes `{id, typed}` lines; scripts/voiceloop runs it here on Linux, on a package of KeyboardCore alone. With a last
/// argument `dictionary`, `typed` is `heard` through the Dictionary alone, as scripts/voiceloop reads a final.
struct Clip: Decodable { let id, heard: String; let field, before: String? }
struct Row: Encodable { let id, typed: String }
struct Saved: Decodable { var memory: TypingMemory }

final class Field: TextDocument {
    var before: String
    var after = ""
    init(_ before: String) { self.before = before }
    var textBeforeInput: String? { before }
    var textAfterInput: String? { after }
    func insert(_ text: String) { before += text }
    func deleteBackward(_ count: Int) { before.removeLast(min(count, before.count)) }
    func moveCursor(by offset: Int) {
        let moved = offset < 0 ? before.count - max(before.count + offset, 0) : min(offset, after.count)
        if offset < 0 { after = before.suffix(moved) + after; before.removeLast(moved) }
        else { before += after.prefix(moved); after.removeFirst(moved) }
    }
}

let arguments = CommandLine.arguments
let lexicon = Lexicon(bytes: Bytes([UInt8](FileManager.default.contents(atPath: arguments[1])!)))!
let vocabulary = try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
var settings = KeyboardSettings()
settings.dictationStyle = DictationStyle(rawValue: arguments[4])!
settings.dictationEditing = DictationEditing(rawValue: arguments[5])!
settings.dictationLists = DictationLists(rawValue: arguments[6])!
settings.autoCapitalization = arguments[7] == "on"
let dictionaryOnly = arguments.count > 8 && arguments[8] == "dictionary"
let corrector = Corrector(source: lexicon)
if arguments[3] != "-" {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    let memory = try decoder.decode(Saved.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3]))).memory
    corrector.changeMemory { $0 = memory }
}
let kinds: [String: InputKind] = ["text": .text, "email": .email, "url": .url, "number": .number, "decimal": .decimal,
                                  "twitter": .twitter, "webSearch": .webSearch]

var lines: [String] = []
while let line = readLine() {
    let clip = try JSONDecoder().decode(Clip.self, from: Data(line.utf8))
    if dictionaryOnly {
        lines.append(String(decoding: try JSONEncoder().encode(Row(id: clip.id, typed: vocabulary.corrected(clip.heard, lexicon: lexicon))), as: UTF8.self))
        continue
    }
    var engine = TypingEngine(traits: InputTraits(kind: kinds[clip.field ?? "text"] ?? .text))
    engine.settings = settings
    engine.corrector = corrector
    let field = Field(clip.before ?? "")
    engine.handle(.dictated(vocabulary.corrected(settings.dictation.written(clip.heard), lexicon: lexicon),
                            plain: vocabulary.corrected(clip.heard, lexicon: lexicon)), in: field)
    let kept = zip(clip.before ?? "", field.before).prefix { $0 == $1 }.count
    lines.append(String(decoding: try JSONEncoder().encode(Row(id: clip.id, typed: String(field.before.dropFirst(kept)))), as: UTF8.self))
}
print(lines.joined(separator: "\n"))
