import Foundation
import KeyboardCore
import Testing
import UIKit
@testable import HexKeyboard

/// The GIF panel against `KlipyStub`, which stands in for KLIPY and its media.
@MainActor
@Suite(.serialized)
struct GifPanelTests {
    let stub = KlipyStub.start()

    @Test func aCopyThatFinishesAfterTheKeyboardIsGoneCallsNothingBack() async throws {
        var panel: GifPanel? = try await opened()
        weak var gone = panel
        var calls = 0
        panel?.changed = { calls += 1 }
        panel?.onCopied = { _ in calls += 1 }
        try tiles(panel)[0].sendActions(for: .touchUpInside)
        try #require(await until { stub.held(.media).count == 1 })
        panel = nil
        stub.finish(.media, with: Data("gif".utf8))
        try await Task.sleep(for: .milliseconds(300))
        #expect(gone == nil, "the keyboard's panels go with it")
        #expect(calls == 0, "nothing calls back into a keyboard that's gone")
    }

    @Test func theLastGifTappedIsTheOneOnTheClipboard() async throws {
        let panel = try await opened()
        var copies = 0
        panel.onCopied = { _ in copies += 1 }
        try tiles(panel)[0].sendActions(for: .touchUpInside)
        try tiles(panel)[1].sendActions(for: .touchUpInside)
        try #require(await until { stub.held(.media).count == 2 })
        let (first, second) = (stub.held(.media)[0], stub.held(.media)[1])
        second.finish(Data("second".utf8))
        try #require(await until { panel.notice != nil })
        first.finish(Data("first".utf8))
        try await Task.sleep(for: .milliseconds(300))
        #expect(copies == 1, "the first GIF, arriving late, doesn't replace the second on the clipboard")
    }

    @Test func reopeningWhileTrendingIsOutSendsNoSecondRequest() async throws {
        stub.holdsFeeds = true
        let panel = try await opened(waitingForTiles: false)
        try #require(await until { stub.held(.feed).count == 1 })
        panel.reset()
        panel.show(query: "", theme: .lightCurrent, metrics: .phone(width: 390))
        try await Task.sleep(for: .milliseconds(300))
        #expect(stub.held(.feed).count == 1, "one request out at a time, across a close and reopen")
        stub.finish(.feed, with: nil)
    }

    @Test func aPreviewThatFailedToLoadTriesAgainWhenItsShownAgain() async throws {
        stub.holdsMedia = false
        stub.failsOnce = true
        let panel = try await opened()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        window.isHidden = false
        window.addSubview(panel)
        panel.layoutIfNeeded()
        try #require(await until { stub.sent(.media) == 2 }, "both tiles on screen load their previews, one failing")
        try await Task.sleep(for: .milliseconds(300))
        panel.removeFromSuperview()
        window.addSubview(panel)
        #expect(await until { stub.sent(.media) == 3 }, "shown again, the failed preview loads again")
    }

    private func opened(waitingForTiles: Bool = true) async throws -> GifPanel {
        let panel = GifPanel(klipy: Klipy(key: "test", customer: "test"))
        panel.fullAccess = { true }
        panel.frame = CGRect(x: 0, y: 0, width: 390, height: 136)
        panel.reset()
        panel.show(query: "", theme: .lightCurrent, metrics: .phone(width: 390))
        if waitingForTiles { try #require(await until { (try? tiles(panel).count) == 2 }) }
        return panel
    }

    private func tiles(_ panel: GifPanel?) throws -> [UIControl] {
        let scroll = try #require(panel?.subviews.compactMap { $0 as? UIScrollView }.first)
        return scroll.subviews.compactMap { $0 as? UIControl }.filter { $0.accessibilityIdentifier?.hasPrefix("hex.gif.") == true }
    }

    @discardableResult
    private func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

/// Answers KLIPY's feeds with `klipy.json` and holds each media download until a test finishes it.
final class KlipyStub: URLProtocol, @unchecked Sendable {
    enum Kind { case feed, media }

    struct Held: Sendable {
        let kind: Kind
        let finish: @Sendable (Data?) -> Void
    }

    nonisolated(unsafe) private static var current: KlipyStub.State?

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _held: [Held] = []
        private var _sent: [Kind: Int] = [:]
        var holdsFeeds = false
        var holdsMedia = true
        var failsOnce = false

        func held(_ kind: Kind) -> [Held] { lock.withLock { _held.filter { $0.kind == kind } } }
        func sent(_ kind: Kind) -> Int { lock.withLock { _sent[kind, default: 0] } }

        func finish(_ kind: Kind, with data: Data?) {
            let finishing = lock.withLock {
                let finishing = _held.filter { $0.kind == kind }
                _held.removeAll { $0.kind == kind }
                return finishing
            }
            finishing.forEach { $0.finish(data) }
        }

        fileprivate func received(_ kind: Kind, _ finish: @escaping @Sendable (Data?) -> Void) {
            let (hold, fail) = lock.withLock {
                _sent[kind, default: 0] += 1
                let fail = kind == .media && failsOnce
                if fail { failsOnce = false }
                let hold = !fail && (kind == .feed ? holdsFeeds : holdsMedia)
                if hold { _held.append(Held(kind: kind, finish: finish)) }
                return (hold, fail)
            }
            if fail { return finish(nil) }
            if !hold { finish(kind == .feed ? KlipyStub.page : Data("gif".utf8)) }
        }
    }

    fileprivate static let page = try! Data(contentsOf: Bundle.module.url(forResource: "klipy", withExtension: "json")!)

    static func start() -> State {
        if current == nil { URLProtocol.registerClass(KlipyStub.self) }
        let state = State()
        current = state
        return state
    }

    override class func canInit(with request: URLRequest) -> Bool {
        ["api.klipy.com", "static.klipy.com"].contains(request.url?.host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let kind: Kind = url.host == "api.klipy.com" ? .feed : .media
        Self.current?.received(kind) { [self] data in
            guard let data else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
