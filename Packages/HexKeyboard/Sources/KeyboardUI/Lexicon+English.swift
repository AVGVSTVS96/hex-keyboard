import Foundation
import KeyboardCore

extension Lexicon {
    public static let english = Lexicon(bytes: .mapped("en", "lexicon"))!
}

extension Network {
    public static let english = Network(bytes: .mapped("en", "network"))!
}

extension Bytes {
    /// A resource mapped into memory, read in place.
    static func mapped(_ name: String, _ type: String) -> Bytes {
        let file = try! NSData(contentsOf: Bundle.module.url(forResource: name, withExtension: type)!, options: .alwaysMapped)
        return Bytes(UnsafeRawBufferPointer(start: file.bytes, count: file.length), owner: file)
    }
}

extension EmojiCatalog {
    nonisolated static let english: EmojiCatalog = {
        let url = Bundle.module.url(forResource: "emoji", withExtension: "txt")!
        return EmojiCatalog(text: try! String(contentsOf: url, encoding: .utf8), search: .english)
    }()
}

extension EmojiSearch {
    nonisolated static let english: EmojiSearch = {
        let url = Bundle.module.url(forResource: "emoji-search", withExtension: "txt")!
        return EmojiSearch(text: try! String(contentsOf: url, encoding: .utf8))
    }()
}
