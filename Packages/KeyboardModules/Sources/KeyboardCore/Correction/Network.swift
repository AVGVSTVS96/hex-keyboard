/// A small LSTM over words, read in place from bytes: how likely each word of its vocabulary is to come next after the
/// words before it, from the last few words, commas and sentence starts.
///
/// Layout: `HXN1`, then four little-endian u32s (words V, embedding width E, hidden width H, spelling bytes), then
/// - words: a u32 offset per word into the spellings, then the spellings (lowercase, each ending in 0), then the word
///   ids in the spellings' byte order (u32 each), padded to four bytes;
/// - f32s: a scale per row of each int8 matrix below (embedding V, input 4H, recurrent 4H, projection E), then the
///   biases (gates 4H, projection E, output V);
/// - int8 matrices, row by row: the embedding (V × E), which also scores the next word, the input (4H × E) and
///   recurrent (4H × H) weights of the gates in PyTorch's order (input, forget, cell, output), the projection (E × H).
public final class Network: Sendable {
    public let bytes: Bytes

    static let header: [UInt8] = Array("HXN1".utf8)
    static let start = 0, unknown = 1, number = 2, comma = 3
    static let specials = ["<s>", "<unk>", "<n>", ","]
    static let window = 16

    let words: Int
    let width: Int
    let hidden: Int
    private let spellings: Int
    private let sorted: Int
    private let scales: Int
    private let biases: Int
    private let matrices: Int

    public convenience init?(bytes: [UInt8]) {
        self.init(bytes: Bytes(bytes))
    }

    public init?(bytes: Bytes) {
        guard bytes.count >= 20, Array(bytes[0..<4]) == Self.header else { return nil }
        self.bytes = bytes
        words = Self.u32(bytes, 4)
        width = Self.u32(bytes, 8)
        hidden = Self.u32(bytes, 12)
        spellings = 20 + words * 4
        sorted = spellings + Self.u32(bytes, 16)
        scales = (sorted + words * 4 + 3) / 4 * 4
        biases = scales + (words + 8 * hidden + width) * 4
        matrices = biases + (4 * hidden + width + words) * 4
        guard bytes.count == matrices + words * width + 4 * hidden * (width + hidden) + width * hidden else { return nil }
    }

    func id(of word: some StringProtocol) -> Int? {
        let key = Array(word.utf8)
        let index = first { compare($0, key, prefix: false) >= 0 }
        return index < words && compare(index, key, prefix: false) == 0 ? id(at: index) : nil
    }

    /// The words that start with `prefix`, as ids, in their spellings' order.
    func ids(startingWith prefix: some StringProtocol) -> [Int] {
        let key = Array(prefix.utf8)
        var index = first { compare($0, key, prefix: true) >= 0 }
        var ids: [Int] = []
        while index < words, compare(index, key, prefix: true) == 0 {
            ids.append(id(at: index))
            index += 1
        }
        return ids
    }

    private func id(at index: Int) -> Int { Self.u32(bytes, sorted + index * 4) }

    /// The first index into the sorted ids where `isAtOrAfter` holds, by binary search.
    private func first(where isAtOrAfter: (Int) -> Bool) -> Int {
        var low = 0, high = words
        while low < high {
            let middle = (low + high) / 2
            if isAtOrAfter(middle) { high = middle } else { low = middle + 1 }
        }
        return low
    }

    /// How the spelling at a sorted index orders against `key`: -1 before, 0 equal (or starting with it, for a prefix), 1 after.
    private func compare(_ index: Int, _ key: [UInt8], prefix: Bool) -> Int {
        var at = spellings + Self.u32(bytes, 20 + id(at: index) * 4)
        for byte in key {
            let stored = bytes[at]
            if stored != byte { return stored < byte ? -1 : 1 }
            at += 1
        }
        return prefix || bytes[at] == 0 ? 0 : 1
    }

    func spelling(of id: Int) -> String {
        let start = spellings + Self.u32(bytes, 20 + id * 4)
        let end = bytes[start...].firstIndex(of: 0)!
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// The tokens before what comes after `text`: its last words, lowercase, with a comma kept as
    /// a token, numbers as one token and a sentence's start (the text's, and after ".", "!", "?" or a new line) as another.
    func tokens(before text: some StringProtocol) -> [Int] {
        var tokens = [Self.start], word = ""
        func end() {
            let trimmed = word.drop { Words.apostrophes.contains($0) }.reversed().drop { Words.apostrophes.contains($0) }.reversed()
            if !trimmed.isEmpty {
                tokens.append(trimmed.contains(where: \.isNumber) ? Self.number : id(of: String(trimmed)) ?? Self.unknown)
            }
            word = ""
        }
        for character in text {
            if Words.isWordCharacter(character) {
                word += character == "’" ? "'" : character.lowercased()
                continue
            }
            end()
            if TypingEngine.sentenceEnders.contains(character) || character.isNewline {
                if tokens.last != Self.start { tokens.append(Self.start) }
            } else if character == "," {
                tokens.append(Self.comma)
            }
        }
        end()
        return tokens
    }

    /// What the network has read: its hidden and cell states.
    struct State: Equatable {
        var hidden: [Float]
        var cell: [Float]
    }

    var start: State { State(hidden: Array(repeating: 0, count: hidden), cell: Array(repeating: 0, count: hidden)) }

    /// The state after reading `tokens` from `state`.
    func read(_ tokens: some Sequence<Int>, from state: State) -> State {
        bytes.withUnsafeBytes { raw in
            var state = state
            let input = matrices + words * width, recurrent = input + 4 * hidden * width
            var x = [Float](repeating: 0, count: width), gates = [Float](repeating: 0, count: 4 * hidden)
            for token in tokens {
                let row = matrices + token * width, s = scale(raw, token)
                for e in 0..<width { x[e] = Float(Int8(bitPattern: raw[row + e])) * s }
                for g in 0..<4 * hidden {
                    gates[g] = bias(raw, g) + scale(raw, words + g) * Self.dot(raw, input + g * width, x)
                        + scale(raw, words + 4 * hidden + g) * Self.dot(raw, recurrent + g * hidden, state.hidden)
                }
                for j in 0..<hidden {
                    let i = Self.sigmoid(gates[j]), f = Self.sigmoid(gates[hidden + j])
                    let cell = 2 * Self.sigmoid(2 * gates[2 * hidden + j]) - 1, o = Self.sigmoid(gates[3 * hidden + j])
                    state.cell[j] = f * state.cell[j] + i * cell
                    state.hidden[j] = o * (2 * Self.sigmoid(2 * state.cell[j]) - 1)
                }
            }
            return state
        }
    }

    /// ln P(word | what it has read) for every word id.
    func logProbabilities(at state: State) -> [Float] {
        bytes.withUnsafeBytes { raw in
            let projection = matrices + words * width + 4 * hidden * (width + hidden)
            let x = (0..<width).map { e in
                bias(raw, 4 * hidden + e) + scale(raw, words + 8 * hidden + e) * Self.dot(raw, projection + e * hidden, state.hidden)
            }
            let logits = (0..<words).map { v in bias(raw, 4 * hidden + width + v) + scale(raw, v) * Self.dot(raw, matrices + v * width, x) }
            let high = logits.max() ?? 0
            let total = Float(Math.log(logits.reduce(0) { $0 + Math.exp(Double($1 - high)) }))
            return logits.map { $0 - high - total }
        }
    }

    private func scale(_ raw: UnsafeRawBufferPointer, _ row: Int) -> Float {
        raw.loadUnaligned(fromByteOffset: scales + row * 4, as: Float.self)
    }

    private func bias(_ raw: UnsafeRawBufferPointer, _ index: Int) -> Float {
        raw.loadUnaligned(fromByteOffset: biases + index * 4, as: Float.self)
    }

    /// What the network expects after some words: P(word) for the words it knows, and for any other its share of what it
    /// leaves to words it doesn't know, in proportion to `below`, P(word) from a model that knows them.
    struct Next {
        let network: Network
        let logProbabilities: [Float]
        /// The share of the lexicon's words the network doesn't know.
        let unknown: Double

        func probability(of word: String, below: Double) -> Double {
            guard let id = network.id(of: Words.plain(word).lowercased()) else {
                return Math.exp(Double(logProbabilities[Network.unknown])) * below / unknown
            }
            return Math.exp(Double(logProbabilities[id]))
        }

        /// The words it finds likeliest that start with `prefix`, likeliest first.
        func likeliest(_ count: Int, startingWith prefix: String = "") -> [String] {
            let ids = prefix.isEmpty ? Array(Network.specials.count..<network.words) : network.ids(startingWith: Words.plain(prefix).lowercased())
            var best: [Int] = []
            for id in ids where id >= Network.specials.count && (best.count < count || logProbabilities[id] > logProbabilities[best[count - 1]]) {
                let at = best.firstIndex { logProbabilities[$0] < logProbabilities[id] } ?? best.count
                best.insert(id, at: at)
                if best.count > count { best.removeLast() }
            }
            return best.map(network.spelling(of:))
        }
    }

    private static func dot(_ raw: UnsafeRawBufferPointer, _ at: Int, _ vector: [Float]) -> Float {
        vector.withUnsafeBufferPointer { values in
            let weights = (raw.baseAddress! + at).assumingMemoryBound(to: Int8.self)
            var sum = SIMD8<Float>()
            var i = 0
            while i + 8 <= values.count {
                let w = SIMD8<Float>(Float(weights[i]), Float(weights[i + 1]), Float(weights[i + 2]), Float(weights[i + 3]),
                                     Float(weights[i + 4]), Float(weights[i + 5]), Float(weights[i + 6]), Float(weights[i + 7]))
                sum += w * UnsafeRawPointer(values.baseAddress! + i).loadUnaligned(as: SIMD8<Float>.self)
                i += 8
            }
            var rest = sum.sum()
            while i < values.count {
                rest += Float(weights[i]) * values[i]
                i += 1
            }
            return rest
        }
    }

    private static func sigmoid(_ x: Float) -> Float {
        Float(1 / (1 + Math.exp(-Double(x))))
    }

    private static func u32<Source: RandomAccessCollection<UInt8>>(_ bytes: Source, _ at: Int) -> Int where Source.Index == Int {
        let low = Int(bytes[at]) | Int(bytes[at + 1]) << 8
        return low | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
    }
}

extension Network {
    /// Packs a trained network, each matrix row quantized to int8 with its own scale. `vocabulary` starts with
    /// `Network.specials`.
    public convenience init(vocabulary: [String], embedding: [[Float]], input: [[Float]], recurrent: [[Float]], gates: [Float],
                            projection: [[Float]], projectionBias: [Float], output: [Float]) {
        var bytes = Self.header
        func append(_ value: Int) {
            for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) }
        }
        func append(_ value: Float) { append(Int(value.bitPattern)) }
        var spellings: [UInt8] = [], offsets: [Int] = []
        for word in vocabulary {
            offsets.append(spellings.count)
            spellings += Array(word.utf8) + [0]
        }
        let hidden = gates.count / 4
        for value in [vocabulary.count, embedding[0].count, hidden, spellings.count] { append(value) }
        offsets.forEach(append)
        bytes += spellings
        vocabulary.indices.sorted { Array(vocabulary[$0].utf8).lexicographicallyPrecedes(Array(vocabulary[$1].utf8)) }.forEach(append)
        while bytes.count % 4 != 0 { bytes.append(0) }
        let rows = [embedding, input, recurrent, projection]
        let scales = rows.map { $0.map { row in max(row.map(abs).max() ?? 0, .leastNormalMagnitude) / 127 } }
        scales.joined().forEach(append)
        (gates + projectionBias + output).forEach(append)
        for (matrix, scales) in zip(rows, scales) {
            for (row, scale) in zip(matrix, scales) {
                bytes += row.map { UInt8(bitPattern: Int8(($0 / scale).rounded())) }
            }
        }
        self.init(bytes: bytes)!
    }
}
