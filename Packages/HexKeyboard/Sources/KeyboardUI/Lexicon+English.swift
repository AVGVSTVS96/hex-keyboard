import Foundation
import KeyboardCore

extension Lexicon {
    static let english: Lexicon? = Bundle.module.url(forResource: "en", withExtension: "lexicon")
        .flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
        .flatMap { Lexicon(bytes: [UInt8]($0)) }
}
