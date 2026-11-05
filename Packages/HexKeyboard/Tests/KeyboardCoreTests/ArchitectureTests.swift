import Foundation
import Testing

struct ArchitectureTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../..").standardized

    @Test func coreImportsNothing() throws {
        let sources = Self.files(in: "Packages/HexKeyboard/Sources/KeyboardCore").filter { $0.pathExtension == "swift" }
        #expect(sources.count > 20)
        for file in sources {
            let imports = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix("import ") }
            #expect(imports.isEmpty, "\(file.lastPathComponent): \(imports)")
        }
    }

    @Test func everyTimerIsOneAgentsAllows() throws {
        let waits = ["asyncAfter", "afterDelay", "Timer.", "Timer(", ".sleep(", "usleep(", "makeTimerSource", "timeoutInterval", "timeout:"]
        let timers = ["key repeat", "long-press", "source answer", "Keep Mic On", "stop waits for quiet"]
        let sources = ["App", "Keyboard", "web/Sources", "Packages/HexKeyboard/Sources"].flatMap(Self.files).filter { $0.pathExtension == "swift" }
        #expect(sources.count > 100)
        for file in sources {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), waits.contains(where: code.contains) else { continue }
                let place = "\(Self.relative(file)):\(number + 1)"
                guard let marker = code.range(of: "// timer: ") else {
                    Issue.record("\(place) waits on a clock. iikb follows real events (a Darwin notification, the recording's end, textDidChange); AGENTS.md › Rules lists the only timers. If this is one of them, mark the line with `// timer: <which>`, one of: \(timers.joined(separator: ", ")).")
                    continue
                }
                let which = code[marker.upperBound...]
                #expect(timers.contains(where: which.hasPrefix) || which.hasPrefix("unlisted ("), "\(place) marks `// timer: \(which)`, which AGENTS.md › Rules doesn't list; use one of: \(timers.joined(separator: ", ")).")
            }
        }
    }

    static func files(in folder: String) -> [URL] {
        let skipped: Set = [".git", "build", ".build", ".swiftpm", "DerivedData", "node_modules", "dist", "raw", "xtool", ".scratch", ".vercel"]
        guard let walk = FileManager.default.enumerator(at: root.appending(path: folder), includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
        var files: [URL] = []
        for case let url as URL in walk {
            if skipped.contains(url.lastPathComponent) { walk.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, values?.fileSize ?? 0 < 2_000_000 { files.append(url) }
        }
        return files
    }

    static func relative(_ file: URL) -> String {
        String(file.standardized.path(percentEncoded: false).dropFirst(root.path(percentEncoded: false).count))
    }
}
