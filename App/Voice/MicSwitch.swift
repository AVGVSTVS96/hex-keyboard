import SwiftUI

/// The microphone switch as a page's last trailing toolbar item, beside whatever else the page puts there. Every page
/// has it except Settings and its pages.
struct MicSwitchItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { MicSwitch() }
            .sharedBackgroundVisibility(.hidden)
    }
}

/// The microphone, on or off, as it really is: on, the keyboard starts each dictation in place, and it stays on until
/// you turn it off here; off, it goes off once what you're saying is written down. The keyboard can't turn it off.
struct MicSwitch: View {
    @State private var flipping: Bool?
    @State private var failure: String?

    var body: some View {
        let listener = Listener.shared
        let on = flipping ?? (listener.isMicOn && !listener.isTurningMicOff)
        HStack(spacing: 8) {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Toggle("Microphone", isOn: Binding(get: { on }, set: flip))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.blue)
                .accessibilityIdentifier("home-mic")
        }
        .alert("Couldn’t Turn On the Microphone", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Settings") { AppStatus.openSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func flip(_ on: Bool) {
        flipping = on
        Task {
            defer { flipping = nil }
            if !on { return await Listener.shared.turnMicOff() }
            do {
                try await Listener.shared.turnMicOn()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
