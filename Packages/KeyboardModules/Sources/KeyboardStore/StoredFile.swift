import Foundation
import os

nonisolated private let log = Logger(subsystem: "com.shahidy.iikb", category: "store")

/// The App Group the app and the keyboard extension share.
nonisolated public enum AppGroup {
    public static let id = "group.com.shahidy.iikb"

    /// The group's Library folder, where both sides can write, since a keyboard can't write the group's root; nil when
    /// the group is missing.
    public static var library: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?.appending(path: "Library")
    }
}

/// A JSON file of iikb's that a person would miss. Reading tells a missing file from one that's there but can't be
/// read (cut short, or written by a build that keeps it another way), and saving never writes over the second: it's
/// moved aside first as `<name>-unread-<seconds>.<ext>`, in the same folder, so the backup still sends it.
nonisolated public struct StoredFile<Value: Codable>: Sendable {
    public enum Read {
        case missing, unreadable, value(Value)

        public var value: Value? {
            if case .value(let value) = self { value } else { nil }
        }
    }

    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    public func read() -> Read {
        guard let data = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? .unreadable : .missing
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let value = try? decoder.decode(Value.self, from: data) else { return .unreadable }
        return .value(value)
    }

    /// Whether `value` was written.
    @discardableResult public func save(_ value: Value) -> Bool {
        do {
            let data = try encoded(value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if case .unreadable = read() {
                let name = url.deletingPathExtension().lastPathComponent + "-unread-\(Int(Date.now.timeIntervalSince1970))"
                try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name).appendingPathExtension(url.pathExtension))
            }
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            log.fault("\(url.lastPathComponent, privacy: .public) not saved: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// JSON has no NaN or infinity, and a plain encoder refuses the whole value over one number, so such a number is
    /// logged and kept as a string, which `read` reads back.
    private func encoded(_ value: Value) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch EncodingError.invalidValue(let number, let context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            log.fault("\(String(describing: number), privacy: .public) at \(path, privacy: .public) in \(url.lastPathComponent, privacy: .public) is saved as a string")
            let encoder = JSONEncoder()
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            return try encoder.encode(value)
        }
    }
}

extension StoredFile.Read: Equatable where Value: Equatable {}
