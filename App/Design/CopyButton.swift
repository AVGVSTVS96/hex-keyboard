import SwiftUI
import UIKit

/// Copies `text`, then says so: the glyph blurs away as a green check springs in on a green disc, "Copied" slides out
/// beside it, a success tap plays, and after a beat it all settles back. One keyframe track runs it, so a second copy
/// starts it over.
struct CopyButton: View {
    let text: String
    @State private var copies = 0

    var body: some View {
        Button {
            copy(text)
            copies += 1
        } label: {
            KeyframeAnimator(initialValue: 0.0, trigger: copies) { done in
                ZStack {
                    Circle()
                        .fill(Color.copied)
                        .scaleEffect(0.4 + 0.6 * done)
                        .opacity(min(done, 1))
                    Image(systemName: "doc.on.doc")
                        .scaleEffect(1 - 0.5 * min(done, 1))
                        .blur(radius: 4 * min(done, 1))
                        .opacity(1 - min(done, 1))
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .scaleEffect(0.3 + 0.7 * done)
                        .blur(radius: 4 * max(1 - done, 0))
                        .opacity(min(done, 1))
                }
                .frame(width: 34, height: 34)
                .overlay(alignment: .leading) {
                    Text("Copied")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.copied)
                        .fixedSize()
                        .opacity(min(done, 1))
                        .offset(x: 10 * (1 - min(done, 1)))
                        .alignmentGuide(.leading) { $0[.trailing] + 8 }
                        .accessibilityHidden(true)
                }
            } keyframes: { _ in
                SpringKeyframe(1, duration: 0.4, spring: .bouncy(duration: 0.4, extraBounce: 0.15))
                LinearKeyframe(1, duration: 1.2)
                CubicKeyframe(0, duration: 0.35)
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copies)
        .accessibilityLabel("Copy")
    }
}

/// A Copy row that answers as `CopyButton` does: its words turn to "Copied" and its glyph to a green check.
struct CopyRow: View {
    let text: String
    @State private var copies = 0

    var body: some View {
        Button {
            copy(text)
            copies += 1
        } label: {
            KeyframeAnimator(initialValue: 0.0, trigger: copies) { done in
                HStack(spacing: 10) {
                    Text(done > 0.5 ? "Copied" : "Copy")
                        .foregroundStyle(done > 0.5 ? Color.copied : Color.blue)
                    Spacer()
                    ZStack {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(Color.blue)
                            .scaleEffect(1 - 0.5 * min(done, 1))
                            .blur(radius: 3 * min(done, 1))
                            .opacity(1 - min(done, 1))
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.copied)
                            .scaleEffect(0.3 + 0.7 * done)
                            .opacity(min(done, 1))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .row()
            } keyframes: { _ in
                SpringKeyframe(1, duration: 0.4, spring: .bouncy(duration: 0.4, extraBounce: 0.15))
                LinearKeyframe(1, duration: 1.2)
                CubicKeyframe(0, duration: 0.35)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copies)
        .accessibilityLabel("Copy")
    }
}

private extension Color {
    /// iOS's green, a shade darker on light pages so "Copied" reads against them.
    static let copied = Color(UIColor { $0.userInterfaceStyle == .dark ? .systemGreen : UIColor(red: 0x24 / 255, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1) })
}

/// Puts text on the clipboard and tells VoiceOver it's there.
func copy(_ text: String) {
    UIPasteboard.general.string = text
    AccessibilityNotification.Announcement("Copied").post()
}
