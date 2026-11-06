import FoundationModels
import UIKit

/// `-iikbJudgeProbe YES` (`scripts/judgeprobe`): times Apple's on-device model choosing among written forms on this
/// iPhone. Each line of `Documents/judge.jsonl` is `{instructions, prompt, choices}`; the model answers with one of
/// the choices (guided generation, greedy). The first question is asked cold, as the app's first after launch; then
/// every question in a new session (warm); then a few after `prewarm` and the second it asks for; then one after 30 s
/// idle. Each answer is a line of `Documents/judge.log`.
nonisolated enum JudgeProbe {
    static var asked: Bool { UserDefaults.standard.bool(forKey: "iikbJudgeProbe") }

    struct Question: Decodable {
        let instructions: String
        let prompt: String
        let choices: [String]
    }

    struct Answer: Encodable {
        let question: Int
        let phase: String
        let pick: Int?
        let ms: Int
        let background: Bool
        let error: String?
    }

    @MainActor static func runIfAsked() {
        guard asked else { return }
        Task.detached {
            await run()
            exit(0)
        }
    }

    private static let log = URL.documentsDirectory.appendingPathComponent("judge.log")

    private static func write(_ line: String) {
        guard let file = try? FileHandle(forWritingTo: log) else { // file: probe log
            try? Data((line + "\n").utf8).write(to: log) // file: probe log
            return
        }
        file.seekToEndOfFile()
        file.write(Data((line + "\n").utf8))
        try? file.close()
    }

    private static func run() async {
        let model = SystemLanguageModel.default
        var header = "availability \(model.availability) thermal \(ProcessInfo.processInfo.thermalState.rawValue)"
        if #available(iOS 27.0, *) { header += " variant \(model.variant.displayName) context \(model.contextSize)" }
        write(header)
        guard model.isAvailable, let data = try? Data(contentsOf: .documentsDirectory.appendingPathComponent("judge.jsonl")) else { // file: probe input
            return write("done")
        }
        let questions = data.split(separator: UInt8(ascii: "\n")).compactMap { try? JSONDecoder().decode(Question.self, from: $0) }
        guard let first = questions.first else { return write("done") }
        await ask(first, 0, phase: "cold")
        for (index, question) in questions.enumerated() { await ask(question, index, phase: "warm") }
        for (index, question) in questions.prefix(5).enumerated() { await ask(question, index, phase: "prewarmed", prewarm: true) }
        try? await Task.sleep(for: .seconds(30))
        await ask(first, 0, phase: "idle 30 s")
        write("done")
    }

    private static func ask(_ question: Question, _ index: Int, phase: String, prewarm: Bool = false) async {
        let session = LanguageModelSession(instructions: question.instructions)
        if prewarm {
            session.prewarm()
            try? await Task.sleep(for: .seconds(1))
        }
        let background = await UIApplication.shared.applicationState == .background
        let began = ContinuousClock.now
        var pick: Int?, failure: String?
        do {
            let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Written", anyOf: question.choices), dependencies: [])
            let response = try await session.respond(to: question.prompt, schema: schema, includeSchemaInPrompt: false,
                                                     options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 96))
            pick = question.choices.firstIndex(of: try response.content.value(String.self))
        } catch {
            failure = "\(error)"
        }
        let elapsed = (ContinuousClock.now - began).components
        let answer = Answer(question: index, phase: phase, pick: pick, ms: Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000),
                            background: background, error: failure)
        if let line = try? JSONEncoder().encode(answer) { write(String(decoding: line, as: UTF8.self)) }
    }
}
