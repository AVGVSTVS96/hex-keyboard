/// The words that most often follow each common word, from the same corpus as the lexicon (`scripts/nextwords.py`).
/// A sentence start is the context `""`.
///
/// Layout: `HXN1`, the context count, a 4-byte offset per context (contexts in UTF-8 order), then per context: its
/// bytes, the weight the lexicon keeps for words not listed (×255), and its likeliest followers with `-ln p` in tenths.
public final class NextWords: Sendable {
    public let bytes: [UInt8]
    private let count: Int

    static let header: [UInt8] = Array("HXN1".utf8)

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 8, Array(bytes[0..<4]) == Self.header else { return nil }
        self.bytes = bytes
        count = Int(Self.u32(bytes, at: 4))
        guard bytes.count >= 8 + count * 4 else { return nil }
    }

    struct Context {
        /// What P(word) from the lexicon is scaled by, for the followers not listed and on top of the listed ones.
        var backoff: Double
        var followers: [(word: String, probability: Double)]

        /// P(word | context), backing off to `p`, the word's probability without the context.
        func probability(of word: String, backingOffTo p: Double) -> Double {
            let listed = followers.first { $0.word.lowercased() == word.lowercased() }?.probability ?? 0
            return listed + backoff * p
        }
    }

    func context(_ previous: String) -> Context? {
        let key = Array(previous.lowercased().utf8)
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            let offset = entry(middle)
            let name = bytes[offset + 1 ..< offset + 1 + Int(bytes[offset])]
            if name.elementsEqual(key) { return context(at: offset) }
            if name.lexicographicallyPrecedes(key) { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    private func entry(_ index: Int) -> Int { Int(Self.u32(bytes, at: 8 + index * 4)) }

    private func context(at offset: Int) -> Context {
        var o = offset + 1 + Int(bytes[offset])
        let backoff = Double(bytes[o]) / 255
        let followers = Int(bytes[o + 1])
        o += 2
        var result: [(word: String, probability: Double)] = []
        for _ in 0..<followers {
            let length = Int(bytes[o])
            let word = String(decoding: bytes[o + 1 ..< o + 1 + length], as: UTF8.self)
            result.append((word, Math.exp(-Double(bytes[o + 1 + length]) / 10)))
            o += 2 + length
        }
        return Context(backoff: backoff, followers: result)
    }

    private static func u32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
