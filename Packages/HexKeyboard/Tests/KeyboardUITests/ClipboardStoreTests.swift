import Foundation
import KeyboardCore
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import KeyboardUI

@MainActor
struct ClipboardStoreTests {
    let pasteboard = UIPasteboard.withUniqueName()
    let folder = URL.temporaryDirectory.appending(path: "clipboard-\(UUID().uuidString)")

    @Test func keepsWhatYouCopyOnceAndOutlivesTheKeyboard() {
        let store = ClipboardStore(folder: folder)
        pasteboard.string = "Meet at 7"
        store.catchUp(pasteboard)
        store.catchUp(pasteboard)
        #expect(store.history.items.map(\.content) == [.text("Meet at 7")], "an unchanged clipboard isn't kept twice")
        #expect(ClipboardStore(folder: folder).history.items.map(\.content) == [.text("Meet at 7")])
    }

    @Test func twoKeyboardsOpenAtOnceKeepEachOthersCopies() {
        let messages = ClipboardStore(folder: folder), notes = ClipboardStore(folder: folder)
        pasteboard.string = "copied in Messages"
        messages.catchUp(pasteboard)
        pasteboard.string = "copied in Notes"
        notes.catchUp(pasteboard)
        messages.setPinned(true, .text("copied in Messages"))
        #expect(ClipboardStore(folder: folder).history.items.map(\.content) == [.text("copied in Messages"), .text("copied in Notes")],
                "the keyboard in Messages read the history before Notes kept a copy, and pinning there kept it")
    }

    @Test func passwordsAreNeverKept() {
        let store = ClipboardStore(folder: folder)
        pasteboard.setItems([[UTType.utf8PlainText.identifier: "hunter2", "org.nspasteboard.ConcealedType": "hunter2"]])
        store.catchUp(pasteboard)
        #expect(store.history.items.isEmpty)
    }

    @Test func whatTheKeyboardCopiesItselfIsSkipped() {
        let store = ClipboardStore(folder: folder)
        pasteboard.setData(Data("GIF89a".utf8), forPasteboardType: UTType.gif.identifier)
        store.skip(changeCount: pasteboard.changeCount)
        store.catchUp(pasteboard)
        #expect(store.history.items.isEmpty)
    }

    @Test func imagesAreKeptAsFilesThatGoBackOnTheClipboardAndAreDeletedWithTheirItem() throws {
        let store = ClipboardStore(folder: folder)
        let png = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        pasteboard.setData(png, forPasteboardType: UTType.png.identifier)
        store.catchUp(pasteboard)
        guard case .image(let name) = try #require(store.history.items.first).content else { Issue.record("not an image"); return }
        #expect(name.hasSuffix(".png"))
        let thumbnail = try #require(store.thumbnail(name, side: 64))
        #expect(max(thumbnail.size.width, thumbnail.size.height) == 64)

        pasteboard.string = "something else"
        store.copy(image: name, to: pasteboard)
        #expect(pasteboard.data(forPasteboardType: UTType.png.identifier) == png)
        store.catchUp(pasteboard)
        #expect(store.history.items.count == 1, "putting it back doesn't keep it again")

        store.remove(.image(name))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: name).path()))
    }

    @Test func theAppSeesWhatTheKeyboardKeptBeforeTheGroupHeldIt() throws {
        let own = URL.temporaryDirectory.appending(path: "clipboard-own-\(UUID().uuidString)")
        let old = ClipboardStore(folder: own)
        pasteboard.string = "kept before"
        old.catchUp(pasteboard)
        #expect(!ClipboardStore(folder: folder).started, "the app keeps nothing until the keyboard brings its history over")

        let keyboard = ClipboardStore(folder: folder, backup: own)
        #expect(keyboard.history.items.map(\.content) == [.text("kept before")])
        pasteboard.string = "kept after"
        keyboard.catchUp(pasteboard)
        let app = ClipboardStore(folder: folder)
        #expect(app.started)
        #expect(app.history.items.map(\.content) == [.text("kept after"), .text("kept before")])

        app.remove(.text("kept before"))
        keyboard.setPinned(true, .text("kept after"))
        #expect(ClipboardStore(folder: own).history.items.map(\.content) == [.text("kept after")], "the keyboard's copy follows what the app deleted")
    }

    @Test func aWipedGroupGetsTheKeyboardsCopyBackImagesIncluded() throws {
        let own = URL.temporaryDirectory.appending(path: "clipboard-own-\(UUID().uuidString)")
        let keyboard = ClipboardStore(folder: folder, backup: own)
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forPasteboardType: UTType.png.identifier)
        keyboard.catchUp(pasteboard)
        guard case .image(let name) = try #require(keyboard.history.items.first).content else { Issue.record("not an image"); return }
        #expect(FileManager.default.fileExists(atPath: own.appending(path: name).path()))

        try FileManager.default.removeItem(at: folder)
        #expect(ClipboardStore(folder: folder, backup: own).history.items.map(\.content) == [.image(name)])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path()))
    }
}
