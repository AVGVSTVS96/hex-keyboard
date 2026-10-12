import Foundation
import KeyboardCore

extension Lexicon {
    static let english: Lexicon = {
        let url = Bundle.module.url(forResource: "en", withExtension: "lexicon")!
        return Lexicon(bytes: [UInt8](try! Data(contentsOf: url, options: .alwaysMapped)))!
    }()
}

extension NextWords {
    static let english: NextWords = {
        let url = Bundle.module.url(forResource: "en", withExtension: "next")!
        return NextWords(bytes: [UInt8](try! Data(contentsOf: url, options: .alwaysMapped)))!
    }()
}
