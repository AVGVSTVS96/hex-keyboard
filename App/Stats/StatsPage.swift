import KeyboardCore
import Charts
import KeyboardStore
import KeyboardUI
import SwiftUI
import notify

/// How you type and talk, and where your taps land, on this iPhone or on a computer you added (docs/computers.md), each
/// apart: Typing, Dictation and Taps as pills under the title, the device in a menu beside it.
struct StatsPage: View {
    enum Section: String, CaseIterable {
        case typing, dictation, taps

        var title: String { rawValue.capitalized }
    }

    enum Device: Hashable {
        case iPhone
        case computer(String)

        var title: String {
            switch self {
            case .iPhone: "iPhone"
            case let .computer(name): name
            }
        }

        var symbol: String { self == .iPhone ? "iphone" : "laptopcomputer" }
    }

    @Bindable private var router = Router.shared
    @State private var phone = PhoneActivity()
    @State private var adding = LaunchOptions.addsComputer
    private let computers = Computers.shared
    @Environment(\.scenePhase) private var phase

    private var device: Device {
        router.statsComputer.flatMap { name in computers.activity[name].map { _ in .computer(name) } } ?? .iPhone
    }
    private var sections: [Section] { device == .iPhone ? Section.allCases : [.typing, .dictation] }
    private var section: Section { sections.contains(router.stats) ? router.stats : .typing }

    var body: some View {
        NavigationStack {
            Group {
                switch (section, device) {
                case (.taps, _): TapsPage()
                case (_, .iPhone): DeviceStats(kind: section == .typing ? .typed : .said, activity: phone.activity, device: .iPhone)
                case let (_, .computer(name)):
                    DeviceStats(kind: section == .typing ? .typed : .said, activity: computers.activity[name] ?? Activity(), device: device)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SectionPills(sections: sections, selection: Binding { section } set: { router.stats = $0 }, title: \.title)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appPage)
            }
            .appPage()
            .navigationTitle("Stats")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { devices }
                MicSwitchItem()
            }
        }
        .sheet(isPresented: $adding) { AddComputer() }
        .onAppear(perform: refresh)
        .onChange(of: phase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        phone.reload()
        Task { await computers.read() }
    }

    private var devices: some View {
        Menu {
            Picker("Device", selection: Binding { device } set: { router.statsComputer = if case let .computer(name) = $0 { name } else { nil } }) {
                ForEach([Device.iPhone] + computers.all.map { .computer($0.name) }, id: \.self) { device in
                    Label(device.title, systemImage: device.symbol).tag(device)
                }
            }
            Button("Add Computer…", systemImage: "plus") { adding = true }
            if case let .computer(name) = device {
                Button("Forget \(name)", systemImage: "trash", role: .destructive) {
                    router.statsComputer = nil
                    computers.remove(name)
                }
            }
        } label: {
            Label(device.title, systemImage: device.symbol)
                .labelStyle(.titleAndIcon)
        }
    }
}

/// The iPhone's typing, from the hours the keyboard shares as it closes, and its dictation, from Transcripts.
@MainActor @Observable private final class PhoneActivity {
    private var hours: [TypingHour] = []
    @ObservationIgnored private var token: Int32 = 0

    var activity: Activity { Activity(hours: hours, transcripts: Transcripts.shared.all) }

    init() {
        hours = TypingStats.shared()
        token = TypingStats.observe { [weak self] in self?.reload() }
    }

    isolated deinit {
        notify_cancel(token)
    }

    func reload() {
        Task {
            hours = await Task.detached(priority: .userInitiated) { TypingStats.shared() }.value
        }
    }
}

/// Raycast's pills for a page's own tabs: a row of titles, the picked one on a filled capsule.
struct SectionPills<Value: Hashable>: View {
    let sections: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var pill

    init(sections: [Value], selection: Binding<Value>, title: @escaping (Value) -> String) {
        self.sections = sections
        _selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sections, id: \.self) { section in
                let picked = section == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) { selection = section }
                } label: {
                    Text(title(section))
                        .font(.body.weight(.medium))
                        .foregroundStyle(picked ? Color.appPillLabel : Color.appSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background {
                            if picked { Capsule().fill(Color.appPill).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
