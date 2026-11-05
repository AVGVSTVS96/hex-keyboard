import Foundation
import HexStore
import Testing

struct StoredFileTests {
    let folder = URL.temporaryDirectory.appending(path: "StoredFile \(UUID().uuidString)/Library")
    var file: StoredFile<[String: Double]> { StoredFile(folder.appending(path: "kept.json")) }

    @Test func readsAMissingFileAsMissing() {
        #expect(file.read() == .missing)
        #expect(file.save(["taps": 3]), "saving makes the folder")
        #expect(file.read() == .value(["taps": 3]))
        file.remove()
        #expect(file.read() == .missing)
    }

    @Test func neverSavesOverAFileItCanNotRead() throws {
        let cut = Data("{\"taps\":".utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try cut.write(to: file.url)
        #expect(file.read() == .unreadable)

        #expect(file.save(["taps": 3]))
        #expect(file.read() == .value(["taps": 3]))
        let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).filter { $0 != "kept.json" }
        #expect(aside.count == 1)
        #expect(aside.first?.hasPrefix("kept-unread-") == true && aside.first?.hasSuffix(".json") == true)
        #expect(try Data(contentsOf: folder.appending(path: aside.first ?? "")) == cut, "the unreadable file is kept as it was")
    }

    @Test func keepsNaNAndInfinity() {
        #expect(file.save(["mean": .nan, "far": .infinity, "taps": 3]))
        let read = file.read().value
        #expect(read?["mean"]?.isNaN == true)
        #expect(read?["far"] == .infinity)
        #expect(read?["taps"] == 3)
    }
}
