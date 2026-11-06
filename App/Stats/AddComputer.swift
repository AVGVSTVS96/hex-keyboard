import SwiftUI

/// How to share a Mac's stats, and a field for the link it shows, for when the camera can't scan its QR code.
struct AddComputer: View {
    @State private var link = ""
    @Environment(\.dismiss) private var dismiss

    static let command = "curl -fsSL https://raw.githubusercontent.com/AVGVSTVS96/iikb/main/mac/share | sh"

    private var computer: Computer? {
        URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(Computer.init(link:))
    }

    var body: some View {
        NavigationStack {
            Column {
                Box(header: "On your Mac", footer: "Run this in Terminal with Keystroke counting there. It shows a QR code: scan it with your iPhone’s camera. With Tailscale on both, iikb reaches the Mac anywhere; without it, on the same Wi‑Fi.") {
                    HStack(alignment: .center, spacing: 12) {
                        Text(Self.command)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: Self.command)
                    }
                    .row()
                }
                Box(footer: link.isEmpty || computer != nil ? "Or paste the link it shows." : "That isn’t a computer’s link: it starts with iikb://computer.") {
                    TextField("iikb://computer?…", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .row()
                }
            }
            .pushedPage("Add Computer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let computer else { return }
                        Computers.shared.add(computer)
                        Router.shared.statsComputer = computer.name
                        dismiss()
                    }
                    .disabled(computer == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.appPage)
    }
}
