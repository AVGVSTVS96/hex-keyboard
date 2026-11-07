import MessageUI
import UIKit

/// A transcript's sound sent on: into a new message as Messages' own audio message format, or through the share sheet
/// as a voice memo (Voice Memos, Files, AirDrop, any app).
@MainActor
enum RecordingShare {
    static func send(_ transcript: Transcript, as kind: Recording.Export) throws {
        let recording = Transcripts.shared.recording(of: transcript.id)
        guard kind == .message, MFMessageComposeViewController.canSendText(), MFMessageComposeViewController.canSendAttachments() else {
            return try share(Recording.export(recording, named: name(transcript), as: .memo))
        }
        let file = try Recording.export(recording, named: "Audio Message", as: .message)
        let compose = MFMessageComposeViewController()
        compose.addAttachmentData(try Data(contentsOf: file), typeIdentifier: "com.apple.coreaudio-format", filename: file.lastPathComponent) // file: recording export
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        compose.messageComposeDelegate = Closer.shared
        top()?.present(compose, animated: true)
    }

    private static func share(_ file: URL) {
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        guard let top = top() else { return }
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(sheet, animated: true)
    }

    private static func name(_ transcript: Transcript) -> String {
        let words = transcript.text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ").filter { !"/:".contains($0) }
        return words.isEmpty ? "iikb Recording" : words
    }

    private static func top() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private final class Closer: NSObject, MFMessageComposeViewControllerDelegate {
        static let shared = Closer()

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}
