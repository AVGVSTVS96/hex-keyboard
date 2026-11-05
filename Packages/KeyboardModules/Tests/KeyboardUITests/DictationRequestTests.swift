import Foundation
import Testing
import KeyboardStore

@MainActor
struct DictationRequestTests {
    @Test func theLinkCarriesTheAppToGoBackTo() {
        let request = Dictation.Request(host: "ph.telegra.Telegraph")
        #expect(request.url.absoluteString == "iikb://dictate?host=ph.telegra.Telegraph")
        #expect(Dictation.Request(request.url) == request)
    }

    @Test func aLinkWithoutAnAppStillDictates() {
        #expect(Dictation.Request(host: nil).url.absoluteString == "iikb://dictate")
        #expect(Dictation.Request(URL(string: "iikb://dictate")!) == Dictation.Request(host: nil))
    }

    @Test func otherLinksAreNotRequests() {
        #expect(Dictation.Request(URL(string: "iikb://source?url=x")!) == nil)
        #expect(Dictation.Request(URL(string: "tg://dictate")!) == nil)
    }
}
