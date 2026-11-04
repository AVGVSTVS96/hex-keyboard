import Foundation
import Testing
@testable import KeyboardCore

private let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/KeyboardUI/Resources")

private func resource(_ name: String) -> Bytes {
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

    /// A swipe whose duration lands on the middle of two 60 Hz step counts can round the other way than Python does,
    /// moving its input: those are left out.
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
        #expect(perSwipe.allSatisfy { $0.encoderP < 1e-3 && $0.decoderP < 1e-3 })
    }
}
