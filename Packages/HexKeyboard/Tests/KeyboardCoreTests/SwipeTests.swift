import Foundation
import Testing
@testable import KeyboardCore

private let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/KeyboardUI/Resources")

func resource(_ name: String) -> Bytes {
    Bytes([UInt8](try! Data(contentsOf: resources.appendingPathComponent(name))))
}

let swipe = Swipe(bytes: resource("en.swipe"))!

/// What ExecuTorch's own runtime says for some real swipes, from `scripts/swipe.py reference`: after the header (`SWR1`,
/// a count, the 26 letter centers of the QWERTY frame the model card gives), per swipe its word, its points (x, y and
/// t in ms), the model's input features, and the encoder's and the decoder's log-probabilities of a–z and a blank.
struct Reference {
    struct Swipe {
        let word: String
        let path: [SwipePoint]
        let features: [Float]
        let encoder: [Float]
        let decoder: [Float]
    }

    let layout: SwipeLayout
    let swipes: [Swipe]

    init(contentsOf url: URL) throws {
        let data = [UInt8](try Data(contentsOf: url))
        var at = 8
        func floats(_ count: Int) -> [Float] {
            defer { at += count * 4 }
            return (0..<count).map { Float(bitPattern: UInt32(data[at + $0 * 4]) | UInt32(data[at + $0 * 4 + 1]) << 8 | UInt32(data[at + $0 * 4 + 2]) << 16 | UInt32(data[at + $0 * 4 + 3]) << 24) }
        }
        func u16() -> Int {
            defer { at += 2 }
            return Int(data[at]) | Int(data[at + 1]) << 8
        }
        let count = Int(data[4]) | Int(data[5]) << 8 | Int(data[6]) << 16
        let keys = floats(52)
        var centers: [Character: (x: Double, y: Double)] = [:]
        for k in 0..<26 { centers[Character(UnicodeScalar(UInt8(97 + k)))] = (Double(keys[2 * k]), Double(keys[2 * k + 1])) }
        layout = SwipeLayout(centers: centers, frame: Rect(x: 0, y: 0, width: 1, height: 1))!
        var swipes: [Swipe] = []
        for _ in 0..<count {
            let length = u16(), points = u16()
            let word = String(decoding: data[at..<at + length], as: UTF8.self)
            at += length
            let raw = floats(points * 3)
            let path = (0..<points).map { SwipePoint(x: Double(raw[3 * $0]), y: Double(raw[3 * $0 + 1]), time: Double(raw[3 * $0 + 2]) / 1000) }
            swipes.append(Swipe(word: word, path: path, features: floats(128), encoder: floats(32 * 27), decoder: floats(32 * 27)))
        }
        self.swipes = swipes
    }
}

/// The largest difference between two runs in P (`.probability`) or in ln P over the entries the reference gives at least
/// `floor`: a log-probability far below that moves by whole nats on a rounding error.
func maxDifference(_ a: [Float], _ b: [Float], probability: Bool = false, above floor: Float = -.infinity) -> Float {
    zip(a, b).filter { $1 > floor }.map { probability ? abs(Float(Math.exp(Double($0))) - Float(Math.exp(Double($1)))) : abs($0 - $1) }.max() ?? 0
}

struct SwipeTests {
    @Test func theModelIsTheSizeItsLayoutSays() {
        #expect(swipe.bytes.count == Swipe.size)
        #expect(Swipe(bytes: [UInt8](repeating: 0, count: 100)) == nil)
    }

    @Test func matchesExecuTorchOnRealSwipes() throws {
        try check(Reference(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("swipe.reference")))
    }

    /// A bigger sample: `SWIPE_REFERENCE=<file> scripts/coretest --filter SwipeTests` (scripts/swipe parity).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIPE_REFERENCE"] != nil))
    func matchesExecuTorchOnASample() throws {
        try check(Reference(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWIPE_REFERENCE"]!)))
    }

    @Test func readsTheLettersOfAKeyGridInTheEncodersFrame() throws {
        let layout = try #require(SwipeLayout(grid: .standard))
        let reference = try Reference(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("swipe.reference"))
        for (mine, theirs) in zip(layout.centers, reference.layout.centers) {
            #expect(abs(mine.x - theirs.x) < 0.01 && abs(mine.y - theirs.y) < 0.01)
        }
    }

    @Test func picksTheWordOfARealSwipeFromTheLexicon() throws {
        let reference = try Reference(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("swipe.reference"))
        let lexicon = Lexicon(counts: [("in", 100.0), ("inn", 1), ("on", 100), ("mother", 10), ("mouthed", 10), ("Brahma's", 1), ("Brahms", 1), ("is", 100)] as [(word: String, count: Double)])
        let expected = ["Brahma's", "in", "mother"]
        for (item, word) in zip(reference.swipes, expected) {
            #expect(swipe.decode(item.path, on: reference.layout, in: lexicon).first?.word == word)
        }
    }

    @Test func swipesThroughLettersFindTheirWordWithoutTheApostrophe() throws {
        let layout = try #require(SwipeLayout(grid: .standard))
        let lexicon = Lexicon(counts: [("I'm", 10.0), ("in", 10), ("on", 10), ("it's", 10), ("its", 5), ("he'll", 10), ("hell", 1), ("the", 10), ("then", 10)] as [(word: String, count: Double)])
        for (letters, word) in [("im", "I'm"), ("its", "it's"), ("hell", "he'll"), ("the", "the"), ("then", "then")] {
            let path = layout.path(through: letters)
            #expect(swipe.decode(path, on: layout, in: lexicon).first?.word == word, "\(letters)")
        }
    }

    @Test func aPathOfOnePointHasNoWords() throws {
        let layout = try #require(SwipeLayout(grid: .standard))
        #expect(swipe.decode([SwipePoint(x: 1, y: 1, time: 0)], on: layout, in: Lexicon(counts: [("in", 1.0)] as [(word: String, count: Double)])).isEmpty)
    }

    /// A swipe whose duration lands on the middle of two 60 Hz step counts can round the other way than Python does,
    /// moving its input: those are left out. A finger that rests at the end of a swipe leaves the Savitzky-Golay
    /// velocities there at rounding noise, whose direction the curvature feature reads; the noise is the same only when
    /// the sums round the same way, so a few swipes differ by more.
    func check(_ reference: Reference) throws {
        var perSwipe: [(encoderP: Float, decoderP: Float, encoder: Float, decoder: Float)] = []
        for item in reference.swipes {
            let resampled = reference.layout.resampled(item.path)
            guard maxDifference(resampled.x + resampled.y, item.features) < 1e-4 else { continue }
            let encoder = try #require(swipe.emissions(of: item.path, on: reference.layout, refined: false)).values
            let decoder = try #require(swipe.emissions(of: item.path, on: reference.layout)).values
            perSwipe.append((maxDifference(encoder, item.encoder, probability: true), maxDifference(decoder, item.decoder, probability: true),
                             maxDifference(encoder, item.encoder, above: -12), maxDifference(decoder, item.decoder, above: -12)))
        }
        func summary(_ values: [Float]) -> String {
            let sorted = values.sorted()
            return "median \(sorted[sorted.count / 2]) max \(sorted.last!)"
        }
        print("SWIPE parity swipes=\(perSwipe.count)/\(reference.swipes.count) per-swipe max |dP|: encoder \(summary(perSwipe.map(\.encoderP))), decoder \(summary(perSwipe.map(\.decoderP))); |d ln P| above -12: encoder \(summary(perSwipe.map(\.encoder))), decoder \(summary(perSwipe.map(\.decoder)))")
        #expect(perSwipe.count * 100 >= reference.swipes.count * 95)
        let worst = perSwipe.map { max($0.encoderP, $0.decoderP) }.sorted()
        #expect(worst[worst.count / 2] < 1e-4 && worst[worst.count * 99 / 100] < 1e-3)
    }
}

extension SwipeLayout {
    /// A finger moving straight from the center of each key to the next at 0.8 key boxes a second, in the keyboard's points.
    func path(through letters: String) -> [SwipePoint] {
        let waypoints = letters.utf8.map { centers[Int($0) - 97] }.map { (x: frame.x + $0.x * frame.width, y: frame.y + $0.y * frame.height) }
        var path = [SwipePoint(x: waypoints[0].x, y: waypoints[0].y, time: 0)]
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let steps = max(Int((((to.x - from.x) / frame.width) * ((to.x - from.x) / frame.width) + ((to.y - from.y) / frame.height) * ((to.y - from.y) / frame.height)).squareRoot() * 12), 2)
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                path.append(SwipePoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t, time: path.last!.time + 1.0 / 60))
            }
        }
        return path
    }
}
