import Foundation
import KeyboardCore
import Testing
@testable import KeyboardUI

struct GifTests {
    @Test func aKlipyPageGivesItsGifsInOrderLeavingOutAdsAndGifsMissingARendition() throws {
        let data = try Data(contentsOf: #require(Bundle.module.url(forResource: "klipy", withExtension: "json")))
        let page = try JSONDecoder().decode(Klipy.Page.self, from: data)
        let gifs = page.data.data.compactMap(\.gif)
        #expect(gifs.map(\.id) == ["goatplaybanjo-chat-4--kw0djle1v", "second-gif"])
        let gif = try #require(gifs.first)
        #expect(gif.title == "Goatplaybanjo's Chatty Cat")
        #expect(gif.preview.url.hasSuffix(".webp"), "the grid gets the small WebP")
        #expect(gif.full.url.hasSuffix(".gif"), "the clipboard gets a GIF, which every app pastes")
        #expect(gif.preview.height > 0 && gif.preview.width > 0)
    }
}
