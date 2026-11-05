import Foundation
import KeyboardCore

extension Lexicon {
    public static let english = Lexicon(bytes: .mapped("en", "lexicon"))!
}

extension Network {
    public static let english = Network(bytes: .mapped("en", "network"))!
}

extension Swipe {
    public static let english = Swipe(bytes: .mapped("en", "swipe"))!
}

extension Bytes {
    /// A resource mapped into memory, read in place.
    static func mapped(_ name: String, _ type: String) -> Bytes {
        mapped(Bundle.module.url(forResource: name, withExtension: type)!)!
    }

    public static func mapped(_ url: URL) -> Bytes? {
        guard let file = try? NSData(contentsOf: url, options: .alwaysMapped) else { return nil } // file: mapped model data
        return Bytes(UnsafeRawBufferPointer(start: file.bytes, count: file.length), owner: file)
    }
}

extension EmojiCatalog {
    public static let english: EmojiCatalog = {
        let url = Bundle.module.url(forResource: "emoji", withExtension: "txt")!
        return EmojiCatalog(text: try! String(contentsOf: url, encoding: .utf8), search: .english) // file: bundled resource
    }()
}

extension EmojiSearch {
    public static let english: EmojiSearch = {
        let url = Bundle.module.url(forResource: "emoji-search", withExtension: "txt")!
        return EmojiSearch(text: try! String(contentsOf: url, encoding: .utf8)) // file: bundled resource
    }()
}
