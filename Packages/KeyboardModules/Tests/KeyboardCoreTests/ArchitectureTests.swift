import Foundation
import Testing

struct ArchitectureTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../..").standardized

    @Test func coreImportsNothing() throws {
        let sources = Self.files(in: "Packages/KeyboardModules/Sources/KeyboardCore").filter { $0.pathExtension == "swift" }
        #expect(sources.count > 20)
        for file in sources {
            let imports = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix("import ") }
            #expect(imports.isEmpty, "\(file.lastPathComponent): \(imports)")
        }
    }

    @Test func everyTimerIsOneAgentsAllows() throws {
        let waits = ["asyncAfter", "afterDelay", "Timer.", "Timer(", ".sleep(", "usleep(", "makeTimerSource", "timeoutInterval", "timeout:"]
        let timers = ["key repeat", "long-press", "source answer", "Keep Mic On", "stop waits for quiet"]
        let sources = ["App", "Keyboard", "web/Sources", "Packages/KeyboardModules/Sources"].flatMap(Self.files).filter { $0.pathExtension == "swift" }
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

    /// From the background iOS refuses to start a stopped microphone, so a restart iikb chooses there turned his
    /// microphone off after each dictation (Duo, Nov 6). Only iOS's own stops, or a function that checks iikb is in front,
    /// may start it again.
    @Test func theMicrophoneRestartsByChoiceOnlyInFront() throws {
        let reasons = ["iOS stopped it", "a picked microphone came or went", "in front"]
        var restarts = 0
        for file in Self.files(in: "App").filter({ $0.pathExtension == "swift" }) {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() where line.contains("restart(") && !line.contains("func restart(") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                restarts += 1
                let place = "\(Self.relative(file)):\(number + 1)"
                guard let marker = line.range(of: "// restart: "), let reason = reasons.first(where: line[marker.upperBound...].hasPrefix) else {
                    Issue.record("\(place) restarts the microphone without saying why; mark it `// restart: <why>`, one of: \(reasons.joined(separator: ", ")).")
                    continue
                }
                guard reason == "in front" else { continue }
                let body = lines[..<number].reversed().prefix { !$0.contains("func ") }
                #expect(body.contains { $0.contains("inFront") }, "\(place) restarts the microphone by choice in a function that doesn't check `Microphone.inFront` first.")
            }
        }
        #expect(restarts >= 4)
    }

    /// A probe's launch is the iikb the keyboard dictates into, so quitting it while the microphone is on turned it off.
    @Test func onlyAFinishedProbeQuits() throws {
        for file in Self.files(in: "App").filter({ $0.pathExtension == "swift" }) {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("exit(") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                #expect(line.contains("// exit: a probe's launch is done") && file.lastPathComponent == "AppDelegate.swift",
                        "\(Self.relative(file)):\(number + 1) quits iikb; a probe ends with `Probe.end()`, which stays while the microphone is on.")
            }
        }
    }

    @Test func keptDataGoesThroughStoredFile() throws {
        let direct = ["Data(contentsOf:", "NSData(contentsOf:", "String(contentsOf:", "String(contentsOfFile:", ".write(to:", ".write(toFile:",
                      "FileHandle(forWritingTo:", "FileHandle(forUpdating", "FileHandle(forReadingFrom:", "createFile(atPath:", "contents(atPath:",
                      "AVAudioFile(forWriting:", "O_CREAT"]
        let sources = ["App", "Packages/KeyboardModules/Sources"].flatMap(Self.files).filter { $0.pathExtension == "swift" && $0.lastPathComponent != "StoredFile.swift" }
        #expect(sources.count > 100)
        for file in sources {
            for (number, line) in try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), direct.contains(where: code.contains) else { continue }
                let reason = code.range(of: "// file: ").map { code[$0.upperBound...].trimmingCharacters(in: .whitespaces) } ?? ""
                if reason.isEmpty {
                    Issue.record("\(Self.relative(file)):\(number + 1) reads or writes a file directly. Kept data goes through StoredFile (KeyboardStore/StoredFile.swift), which never saves over a file it couldn't read; if this isn't kept data, mark the line `// file: <what it is>`.")
                }
            }
        }
    }

    @Test func agentsNamesOnlyCodeThatExists() throws {
        let files = Self.files(in: ".")
        var words = Set(files.map { $0.deletingPathExtension().lastPathComponent })
        for file in files where file.pathExtension != "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let code = file.pathExtension == "swift" ? text.split(separator: "\n").map { $0.split(separator: "//", maxSplits: 1).first ?? "" }.joined(separator: " ") : text
            words.formUnion(code.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init))
        }
        let docs = files.filter { $0.lastPathComponent == "AGENTS.md" }
        #expect(docs.count > 5)
        for doc in docs {
            let agents = try String(contentsOf: doc, encoding: .utf8)
            for quoted in agents.split(separator: "`").enumerated().filter({ $0.offset % 2 == 1 }).map(\.element) {
                let name = quoted.split(separator: "(").first ?? quoted
                let parts = name.split(separator: ".", omittingEmptySubsequences: false)
                guard parts.allSatisfy({ $0.first.map { $0.isLetter || $0 == "_" } == true && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } }),
                      parts.count == 1 || parts[0].first!.isUppercase else { continue }
                let stale = parts.contains { !words.contains(String($0)) }
                #expect(!stale, "\(Self.relative(doc)) names `\(quoted)`, which no code declares or uses; rename it to what replaced it or drop it.")
            }
        }
    }

    @Test func noConflictMarkers() {
        for file in Self.files(in: ".") {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where ["<<<<<<<", "|||||||", ">>>>>>>"].contains(where: { line == $0 || line.hasPrefix($0 + " ") }) {
                Issue.record("\(Self.relative(file)):\(number + 1) is a merge conflict marker; keep the side that's right, merge the two, and delete the markers.")
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
