/// Words you kept in one app. Shared vocabulary remains the fallback for a new app or context.
public struct AppWords: Codable, Hashable, Sendable {
    private(set) var counts: [String: Int] = [:]
    private(set) var following: [String: [String: Int]] = [:]
    private(set) var total = 0

    public init() {}

    mutating func record(_ word: String, after previous: String?) {
        counts[word, default: 0] += 1
        total += 1
        if let previous { following[previous, default: [:]][word, default: 0] += 1 }
        if counts.count > TypingMemory.capacity {
            counts = counts.filter { $0.value > 1 }
            total = counts.values.reduce(0, +)
            following = following.compactMapValues {
                let next = $0.filter { $0.value > 1 }
                return next.isEmpty ? nil : next
            }
        }
    }

    mutating func forget(_ word: String, after previous: String?) {
        guard let count = counts[word] else { return }
        counts[word] = count > 1 ? count - 1 : nil
        total -= 1
        if let previous, let count = following[previous]?[word] {
            following[previous]?[word] = count > 1 ? count - 1 : nil
        }
    }

    func probability(of word: String, after previous: String?, below fallback: Double) -> Double {
        func blend(_ counts: [String: Int], total: Int, below p: Double) -> Double {
            guard total > 0 else { return p }
            let capitalized = word.first?.isLowercase == true ? counts[word.prefix(1).uppercased() + word.dropFirst(), default: 0] : 0
            return (Double(counts[word, default: 0] + capitalized) + Double(counts.count) * p) / Double(total + counts.count)
        }
        let p = blend(counts, total: total, below: fallback)
        guard let previous, let next = following[previous] else { return p }
        return blend(next, total: next.values.reduce(0, +), below: p)
    }
}
