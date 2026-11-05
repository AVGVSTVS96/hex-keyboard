import Foundation
import KeyboardCore
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import HexStore

@MainActor
struct ClipboardStoreTests {
    let pasteboard = UIPasteboard.withUniqueName()
    let folder = URL.temporaryDirectory.appending(path: "App Group \(UUID().uuidString)/clipboard")

    @Test func keepsWhatYouCopyOnceAndOutlivesTheKeyboard() async {
        let store = ClipboardStore(folder: folder)
        pasteboard.string = "Meet at 7"
        await keep(store)
        await keep(store)
        #expect(store.history.items.map(\.content) == [.text("Meet at 7")], "an unchanged clipboard isn't kept twice")
        #expect(await read(folder).history.items.map(\.content) == [.text("Meet at 7")])
    }

    @Test func nothingIsReadOnTheMainThread() async {
        pasteboard.string = "Meet at 7"
        await keep(ClipboardStore(folder: folder))
        let store = ClipboardStore(folder: folder)
        #expect(!store.loaded, "making a store reads nothing")
        store.catchUp(pasteboard)
        #expect(!store.loaded, "catching up reads the history on the store's queue")
        await store.settled()
        #expect(store.history.items.map(\.content) == [.text("Meet at 7")])
    }

    @Test func twoKeyboardsOpenAtOnceKeepEachOthersCopies() async {
        let messages = ClipboardStore(folder: folder), notes = ClipboardStore(folder: folder)
        pasteboard.string = "copied in Messages"
        await keep(messages)
        pasteboard.string = "copied in Notes"
        await keep(notes)
        messages.setPinned(true, .text("copied in Messages"))
        await messages.settled()
        #expect(await read(folder).history.items.map(\.content) == [.text("copied in Messages"), .text("copied in Notes")],
                "the keyboard in Messages read the history before Notes kept a copy, and pinning there kept it")
    }

    @Test func passwordsAreNeverKept() async {
        let store = ClipboardStore(folder: folder)
        pasteboard.setItems([[UTType.utf8PlainText.identifier: "hunter2", "org.nspasteboard.ConcealedType": "hunter2"]])
        await keep(store)
        #expect(store.history.items.isEmpty)
    }

    @Test func whatTheKeyboardCopiesItselfIsSkipped() async {
        let store = ClipboardStore(folder: folder)
        pasteboard.setData(Data("GIF89a".utf8), forPasteboardType: UTType.gif.identifier)
        store.skip(changeCount: pasteboard.changeCount)
        await keep(store)
        #expect(store.history.items.isEmpty)
    }

    @Test func imagesAreKeptAsFilesThatGoBackOnTheClipboardAndAreDeletedWithTheirItem() async throws {
        let store = ClipboardStore(folder: folder)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        pasteboard.setData(png, forPasteboardType: UTType.png.identifier)
        await keep(store)
        guard case .image(let name) = try #require(store.history.items.first).content else { Issue.record("not an image"); return }
        #expect(name.hasSuffix(".png"))
        let thumbnail = try #require(store.thumbnail(name, side: 64))
        #expect(max(thumbnail.size.width, thumbnail.size.height) == 64)

        pasteboard.string = "something else"
        store.copy(image: name, to: pasteboard)
        await store.settled()
        #expect(pasteboard.data(forPasteboardType: UTType.png.identifier) == png)
        await keep(store)
        #expect(store.history.items.count == 1, "putting it back doesn't keep it again")

        store.remove(.image(name))
        #expect(store.history.items.isEmpty, "a deleted row goes at once")
        await store.settled()
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)))
    }

    @Test func theAppSeesWhatTheKeyboardKeptBeforeTheGroupHeldIt() async throws {
        let own = URL.temporaryDirectory.appending(path: "Application Support \(UUID().uuidString)/clipboard")
        pasteboard.string = "kept before"
        await keep(ClipboardStore(folder: own))
        #expect(!ClipboardStore(folder: folder).started, "the app keeps nothing until the keyboard brings its history over")

        let keyboard = await read(folder, backup: own)
        #expect(keyboard.history.items.map(\.content) == [.text("kept before")])
        pasteboard.string = "kept after"
        await keep(keyboard)
        let app = await read(folder)
        #expect(app.started)
        #expect(app.history.items.map(\.content) == [.text("kept after"), .text("kept before")])

        app.remove(.text("kept before"))
        await app.settled()
        keyboard.setPinned(true, .text("kept after"))
        await keyboard.settled()
        #expect(await read(own).history.items.map(\.content) == [.text("kept after")], "the keyboard's copy follows what the app deleted")
    }

    @Test func whatTheKeyboardKeptJoinsAGroupThatAlreadyHasAHistory() async {
        let own = URL.temporaryDirectory.appending(path: "Application Support \(UUID().uuidString)/clipboard")
        pasteboard.string = "kept before"
        await keep(ClipboardStore(folder: own))
        pasteboard.string = "kept in the group"
        await keep(ClipboardStore(folder: folder))
        FileManager.default.createFile(atPath: own.appending(path: "lost.gif").path(percentEncoded: false), contents: Data("GIF89a".utf8))

        let keyboard = await read(folder, backup: own)
        #expect(Set(keyboard.history.items.map(\.content)) == [.text("kept before"), .text("kept in the group"), .image("lost.gif")], "an image whose row was lost gets it back")
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "lost.gif").path(percentEncoded: false)))
        keyboard.remove(.text("kept before"))
        await keyboard.settled()
        #expect(Set(await read(folder, backup: own).history.items.map(\.content)) == [.text("kept in the group"), .image("lost.gif")], "it joins once, so what you delete stays deleted")
        #expect(FileManager.default.fileExists(atPath: own.appending(path: "lost.gif").path(percentEncoded: false)), "the keyboard's copy keeps its images")
    }

    @Test func aWipedGroupGetsTheKeyboardsCopyBackImagesIncluded() async throws {
        let own = URL.temporaryDirectory.appending(path: "Application Support \(UUID().uuidString)/clipboard")
        let keyboard = ClipboardStore(folder: folder, backup: own)
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forPasteboardType: UTType.png.identifier)
        await keep(keyboard)
        guard case .image(let name) = try #require(keyboard.history.items.first).content else { Issue.record("not an image"); return }
        #expect(FileManager.default.fileExists(atPath: own.appending(path: name).path(percentEncoded: false)))

        try FileManager.default.removeItem(at: folder)
        #expect(await read(folder, backup: own).history.items.map(\.content) == [.image(name)])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)))
    }

    @Test func largeTextLivesInAFileAndSurvivesTheGroupBeingLost() async throws {
        let own = URL.temporaryDirectory.appending(path: "clipboard-backup-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: own)
            try? FileManager.default.removeItem(at: folder)
        }
        let text = String(repeating: "🙂é\n", count: 300_000) + "find this tail"
        let store = ClipboardStore(folder: folder, backup: own)
        pasteboard.string = text
        await keep(store)
        let item = try #require(store.history.items.first)
        guard case .textFile(let name, let preview) = item.content else {
            Issue.record("large text must be stored separately")
            return
        }
        #expect(preview == String(text.prefix(300)))
        #expect(try Data(contentsOf: folder.appending(path: "history.json")).count < 10_000)
        #expect(try String(contentsOf: folder.appending(path: name), encoding: .utf8) == text)
        #expect(try String(contentsOf: own.appending(path: name), encoding: .utf8) == text)
        #expect(await store.matching("FIND THIS TAIL").map(\.content) == [item.content])
        store.setPinned(true, item.content)
        await store.settled()
        pasteboard.string = text
        await keep(store)
        #expect(store.history.items.count == 1)
        #expect(store.history.items.first?.pinned == true)
        try FileManager.default.removeItem(at: folder)
        let restored = await read(folder, backup: own)
        #expect(restored.history.items.count == 1)
        #expect(restored.history.items.first?.pinned == true)
        #expect(await restored.text(item.content) == text)
        restored.removeUnpinned()
        await restored.settled()
        #expect(restored.history.items.count == 1)
        restored.remove(item.content)
        await restored.settled()
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: name).path))
        #expect(!FileManager.default.fileExists(atPath: own.appending(path: name).path))
    }

    private func keep(_ store: ClipboardStore) async {
        store.catchUp(pasteboard)
        await store.settled()
    }

    private func read(_ folder: URL, backup: URL? = nil) async -> ClipboardStore {
        let store = ClipboardStore(folder: folder, backup: backup)
        store.reload()
        await store.settled()
        return store
    }
}
