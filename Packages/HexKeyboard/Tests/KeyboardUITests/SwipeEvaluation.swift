import Dispatch
import Foundation
import Testing
@testable import KeyboardCore
@testable import KeyboardUI

/// How well swipes are read, on swipe.futo.org's test split (MIT; `scripts/swipe data` writes it to `SWIPE_DATA`): the
/// share of swipes whose word is the first, among the first three and among the first ten candidates, with iikb's own
/// lexicon and with the targets added to it as the technical report does, from the encoder alone and with the decoder.
private final class Slots<Value: Sendable>: @unchecked Sendable {
    let lock = NSLock()
    var values: [Value?]
    init(_ count: Int) { values = Array(repeating: nil, count: count) }
}

extension Evaluation {
    struct Swipes {
        struct Item {
            let word: String
            let path: [SwipePoint]
            var context = ""
        }

        let items: [Item]

        /// The same swipes as touches on `layout`'s keyboard: the dataset's coordinates are fractions of the letter keys' box.
        func placed(on layout: SwipeLayout) -> [Item] {
            items.map { item in
                Item(word: item.word, path: item.path.map { SwipePoint(x: layout.frame.x + $0.x * layout.frame.width, y: layout.frame.y + $0.y * layout.frame.height, time: $0.time) }, context: item.context)
            }
        }

        static var directory: URL {
            URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIPE_DATA"] ?? "build/swipe")
        }

        static func exists(_ split: String) -> Bool {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(split).swipes").path)
        }

        init(items: [Item]) { self.items = items }

        /// The swipes whose word is letters and apostrophes, after trimming punctuation, of at least two letters.
        init(_ split: String, limit: Int = .max) throws {
            let data = [UInt8](try Data(contentsOf: Self.directory.appendingPathComponent("\(split).swipes")))
            func u32(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24 }
            var at = 8
            var items: [Item] = []
            let contexts = (try? String(contentsOf: Self.directory.appendingPathComponent("\(split).context"), encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: false)
            for index in 0..<u32(4) where items.count < limit {
                let length = Int(data[at]) | Int(data[at + 1]) << 8, count = Int(data[at + 2]) | Int(data[at + 3]) << 8
                let raw = String(decoding: data[at + 4..<at + 4 + length], as: UTF8.self)
                at += 4 + length
                let numbers = data[at..<at + count * 12].withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                at += count * 12
                let word = raw.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
                guard word.utf8.allSatisfy({ Lexicon.index(of: $0) != nil }), word.utf8.count(where: { $0 != 39 }) >= 2 else { continue }
                items.append(Item(word: word, path: (0..<count).map { SwipePoint(x: Double(numbers[3 * $0]), y: Double(numbers[3 * $0 + 1]), time: Double(numbers[3 * $0 + 2]) / 1000) },
                                  context: contexts.flatMap { index < $0.count ? String($0[index]) : nil } ?? ""))
            }
            self.items = items
        }
    }

    /// The lexicon with each of `words` it lacks added at ln P = -`floor` (25.5 is the lowest it stores).
    static func lexicon(adding words: some Sequence<String>, at floor: Double) -> Lexicon {
        var entries: [(word: String, count: Double)] = []
        var seen = Set<String>()
        func visit(_ node: Lexicon.Node, _ spelling: [UInt8]) {
            if let log = Lexicon.english.logWord(node) {
                let word = String(decoding: spelling, as: UTF8.self)
                entries.append((word, Math.exp(log)))
                seen.insert(word.lowercased())
            }
            for child in Lexicon.english.children(node) { visit(child, spelling + [Lexicon.english.letter(child)]) }
        }
        visit(Lexicon.english.root, [])
        for word in Set(words) where !seen.contains(word) { entries.append((word, Math.exp(-floor))) }
        return Lexicon(counts: entries)
    }

    /// `body` for each of 0..<count on every core, in order.
    static func parallel<Result: Sendable>(_ count: Int, _ body: @Sendable (Int) -> Result) -> [Result] {
        let slots = Slots<Result>(count)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let value = body(i)
            slots.lock.lock()
            slots.values[i] = value
            slots.lock.unlock()
        }
        return slots.values.map { $0! }
    }

    static var layout: SwipeLayout {
        SwipeLayout(grid: KeyGrid(Layouts.layout(for: LayoutContext(device: .phone, layer: .letters)), width: width,
                                  metrics: KeyboardMetrics.phone(width: width).grid, signature: "swipe"))!
    }

    struct Accuracy {
        var first = 0, three = 0, ten = 0, total = 0

        mutating func add(_ words: [String], _ target: String) {
            total += 1
            guard let rank = words.firstIndex(of: target) else { return }
            if rank < 1 { first += 1 }
            if rank < 3 { three += 1 }
            ten += 1
        }

        func percent(_ count: Int) -> String { String(format: "%.2f", 100 * Double(count) / Double(max(total, 1))) }
        var summary: String { "top1=\(percent(first)) top3=\(percent(three)) top10=\(percent(ten))" }
    }

    @Test(.enabled(if: Swipes.exists("test")))
    func swipe() throws {
        let layout = Self.layout, model = Swipe.english
        let swipes = Swipes(items: try Swipes("test", limit: Int(ProcessInfo.processInfo.environment["SWIPE_LIMIT"] ?? "") ?? .max).placed(on: layout))
        let targets = Set(swipes.items.map(\.word))
        let ours = Lexicon.english
        let inLexicon = swipes.items.count { ours.logProbability(of: $0.word) != nil }
        print("EVAL swipe swipes=\(swipes.items.count) inLexicon=\(String(format: "%.2f", 100 * Double(inLexicon) / Double(swipes.items.count)))%")
        for refined in [false, true] {
            let emissions = Self.parallel(swipes.items.count) { model.emissions(of: swipes.items[$0].path, on: layout, refined: refined)! }
            for (name, lexicon) in [("ours", ours)] + [25.5, 18.0, 12.0].map({ ("forced at -\($0)", Self.lexicon(adding: targets, at: $0)) }) {
                let ranked = Self.parallel(swipes.items.count) { Swipe.rank(emissions[$0], in: lexicon, refined ? .refined : .encoderOnly, limit: 10).map { $0.word.lowercased() } }
                var accuracy = Accuracy()
                for (item, words) in zip(swipes.items, ranked) { accuracy.add(words, item.word) }
                print("EVAL swipe \(refined ? "encoder+decoder" : "encoder") lexicon=\(name) \(accuracy.summary)")
            }
        }
    }

    /// One decode's cost on one core, from the points to the ranked words.
    @Test(.enabled(if: Swipes.exists("test")))
    func swipeLatency() throws {
        let layout = Self.layout
        let swipes = Swipes(items: try Swipes("test", limit: 600).placed(on: layout))
        let clock = ContinuousClock(), model = Swipe.english, lexicon = Lexicon.english
        for refined in [false, true] {
            var network: [Double] = [], search: [Double] = []
            for item in swipes.items {
                let start = clock.now
                let emissions = model.emissions(of: item.path, on: layout, refined: refined)!
                let middle = clock.now
                _ = Swipe.rank(emissions, in: lexicon, refined ? .refined : .encoderOnly, limit: 10)
                let end = clock.now
                network.append(Double((middle - start).components.attoseconds) / 1e15 + Double((middle - start).components.seconds) * 1000)
                search.append(Double((end - middle).components.attoseconds) / 1e15 + Double((end - middle).components.seconds) * 1000)
            }
            func summary(_ values: [Double]) -> String {
                let sorted = values.sorted()
                return String(format: "median %.2f p95 %.2f", sorted[sorted.count / 2], sorted[sorted.count * 95 / 100])
            }
            print("EVAL latency swipe ms \(refined ? "encoder+decoder" : "encoder"): network \(summary(network)) | search \(summary(search)) | both \(summary(zip(network, search).map(+)))")
        }
    }

    /// Retunes `Swipe.Scoring` on the validation split by coordinate search, keeping the best of top 1 and top 3 together:
    /// `SWIPE_TUNE=refined|encoder scripts/eval swipeTune`, printing the constants to put in `Swipe.Scoring`.
    @Test(.enabled(if: Swipes.exists("dev") && ProcessInfo.processInfo.environment["SWIPE_TUNE"] != nil))
    func swipeTune() throws {
        let refined = ProcessInfo.processInfo.environment["SWIPE_TUNE"] == "refined"
        let layout = Self.layout, model = Swipe.english, lexicon = Lexicon.english
        let swipes = try Swipes("dev", limit: Int(ProcessInfo.processInfo.environment["SWIPE_LIMIT"] ?? "") ?? 8000).placed(on: layout)
        let emissions = Self.parallel(swipes.count) { model.emissions(of: swipes[$0].path, on: layout, refined: refined)! }
        func score(_ scoring: Swipe.Scoring) -> (Double, Accuracy) {
            let ranked = Self.parallel(swipes.count) { Swipe.rank(emissions[$0], in: lexicon, scoring, limit: 3).map { $0.word.lowercased() } }
            var accuracy = Accuracy()
            for (item, words) in zip(swipes, ranked) { accuracy.add(words, item.word) }
            return (Double(accuracy.first + accuracy.three) / Double(accuracy.total), accuracy)
        }
        var best = refined ? Swipe.Scoring.refined : .encoderOnly
        if let b = ProcessInfo.processInfo.environment["SWIPE_BEAM"] { best.beam = Int(b)! }
        if let c = ProcessInfo.processInfo.environment["SWIPE_CUTOFF"] { best.cutoff = Float(c)! }
        var (value, accuracy) = score(best)
        print("EVAL tune start \(accuracy.summary) \(best)")
        let fields: [WritableKeyPath<Swipe.Scoring, Double>] = [\.gamma, \.lambda, \.beta, \.pruneGamma, \.pruneBeta]
        for factor in [1.5, 1.25, 1.1] {
            for field in fields {
                for direction in [factor, 1 / factor] {
                    var trial = best
                    trial[keyPath: field] *= direction
                    let (trialValue, trialAccuracy) = score(trial)
                    if trialValue > value { (best, value, accuracy) = (trial, trialValue, trialAccuracy) }
                }
            }
            print("EVAL tune factor=\(factor) \(accuracy.summary) \(best)")
        }
    }

    /// How much the sentence helps: every swipe of a split read with its sentence's words before it, through the bar's own
    /// next-word model (`Corrector.continuation`, a fresh memory). The grid search over α, λ and β runs on the validation
    /// split (`SWIPE_LIMIT` swipes, every few-th, 6000 by default) with the candidates of the first 30 re-scored exactly,
    /// since the score is linear in λ and β; the test split reports no context against the best settings.
    @Test(.enabled(if: Swipes.exists("dev") && Swipes.exists("test")))
    func swipeContext() throws {
        let layout = Self.layout, model = Swipe.english, lexicon = Lexicon.english
        let base = Swipe.Scoring.refined
        let limit = Int(ProcessInfo.processInfo.environment["SWIPE_LIMIT"] ?? "") ?? 6000

        struct Read {
            let word: String
            let candidates: [(word: String, score: Double, prior: Double, length: Double, context: Double)]
        }
        func read(_ items: [Swipes.Item]) -> [Read] {
            let ranked = Self.parallel(items.count) { index in
                model.emissions(of: items[index].path, on: layout).map { Swipe.rank($0, in: lexicon, base, limit: 30) } ?? []
            }
            let corrector = Corrector(source: lexicon, network: .english)
            return zip(items, ranked).map { item, found in
                let continues = corrector.continuation(after: item.context.isEmpty ? "" : item.context + " ")
                return Read(word: item.word, candidates: found.map {
                    ($0.word, $0.score, lexicon.logProbability(of: $0.word) ?? 0, Double($0.word.utf8.count(where: { $0 != 39 })), continues($0.word))
                })
            }
        }
        func accuracy(_ reads: [Read], alpha: Double, lambda: Double, beta: Double) -> Accuracy {
            var accuracy = Accuracy()
            for item in reads {
                let words = item.candidates
                    .map { ($0.word, $0.score + (lambda - base.lambda) * $0.prior + (beta - base.beta) * $0.length + alpha * $0.context) }
                    .sorted { $0.1 > $1.1 }.prefix(3).map { $0.0.lowercased() }
                accuracy.add(Array(words), item.word)
            }
            return accuracy
        }

        let all = try Swipes("dev").placed(on: layout)
        let stride = max(all.count / limit, 1)
        let dev = read((0..<min(limit, all.count)).map { all[$0 * stride] })
        var best = (alpha: 0.0, lambda: base.lambda, beta: base.beta), bestValue = 0.0
        for alpha in [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.3] {
            for lambda in [0.1, 0.15, 0.2, 0.31] {
                for beta in [0.727, 0.85, 1.0, 1.2, 1.4] {
                    let result = accuracy(dev, alpha: alpha, lambda: lambda, beta: beta)
                    let value = Double(result.first + result.three) / Double(result.total)
                    if value > bestValue { (best, bestValue) = ((alpha, lambda, beta), value) }
                }
            }
        }
        let tuned = accuracy(dev, alpha: best.alpha, lambda: best.lambda, beta: best.beta)
        print("EVAL swipe context dev=\(dev.count) none: \(accuracy(dev, alpha: 0, lambda: base.lambda, beta: base.beta).summary) | alpha=\(best.alpha) lambda=\(best.lambda) beta=\(best.beta): \(tuned.summary)")

        let test = read(try Swipes("test").placed(on: layout))
        print("EVAL swipe context test=\(test.count) none: \(accuracy(test, alpha: 0, lambda: base.lambda, beta: base.beta).summary)")
        print("EVAL swipe context test=\(test.count) alpha=\(best.alpha) lambda=\(best.lambda) beta=\(best.beta): \(accuracy(test, alpha: best.alpha, lambda: best.lambda, beta: best.beta).summary)")
    }
}
