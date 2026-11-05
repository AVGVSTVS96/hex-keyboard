import SwiftUI

/// The microphone's switch, alone at a page's trailing edge on every page but Settings and its pages: one glass capsule
/// iikb draws itself, so it sits in the title row on every screen of the Duo. A page's other actions live in the page
/// or in Settings, since iOS moves a bar button to the Duo's side bar on some screens and not others.
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
        HStack(spacing: 10) {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
                .font(.body)
                .foregroundStyle(on ? Color.primary : Color.appSecondary)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Toggle("Microphone", isOn: Binding(get: { on }, set: flip))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.blue)
                .accessibilityIdentifier("home-mic")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
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
