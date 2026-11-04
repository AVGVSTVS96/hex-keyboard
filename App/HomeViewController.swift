import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// Hex's home (docs/design.md, "The app"): whether the keyboard is on and what's left to set up, the microphone's
/// switch, a field to try it, tiles for today's dictation and your taps, and a card for each setting you reach for,
/// opening its page in Settings.
final class HomeViewController: UIHostingController<AnyView> {
    private let field: UITextView
    private let state: HomeState

    init() {
        let field = UITextView(), state = HomeState()
        self.field = field
        self.state = state
        super.init(rootView: AnyView(NavigationStack { HomeView(state: state, field: field) }.readsWindow()))
        title = "iikb"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = HexStyle.page
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .clear
        field.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
        field.accessibilityLabel = "Try iikb"
        LaunchOptions.configure(field)
        state.typed = !field.text.isEmpty
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(edited), name: UITextView.textDidChangeNotification, object: field)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let orientation = LaunchOptions.orientation {
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
        if LaunchOptions.focus { field.becomeFirstResponder() }
    }

    @objc private func refresh() {
        state.refresh()
    }

    @objc private func edited() {
        state.typed = !field.text.isEmpty
    }
}

/// What the home screen reads that isn't the keyboard's status, read again whenever Hex comes forward.
@Observable final class HomeState {
    var taps = 0
    var copied = 0
    var typed = false
    @ObservationIgnored private lazy var clipboard: ClipboardStore = {
        let store = ClipboardStore()
        store.onChange = { [unowned self, unowned store] in copied = store.history.items.count }
        return store
    }()

    func refresh() {
        HexStatus.shared.refresh()
        taps = MemoryStore.sharedTouches()?.signatures.reduce(0) { $0 + $1.taps } ?? 0
        clipboard.reload()
    }
}

/// Wide, the field and what Hex has gathered take the first half and the settings' cards the second, so the field
/// stays above the keys while you try them; elsewhere, one column.
struct HomeView: View {
    let state: HomeState
    let field: UITextView
    private let status = HexStatus.shared
    @Environment(\.arrangement) private var arrangement

    var body: some View {
        Group {
            switch arrangement {
            case .side:
                Panes {
                    VStack(alignment: .leading, spacing: 12) {
                        tryIt.frame(maxHeight: 300)
                        stats
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                } second: {
                    Column(top: 12) {
                        if !status.isSetUp { setUp }
                        shortcutCards
                    }
                }
            case .single:
                Column(top: 4) {
                    tryIt.frame(height: 150)
                    if !status.isSetUp { setUp }
                    VStack(spacing: 12) {
                        stats
                        shortcutCards
                    }
                }
            }
        }
        .hexPage()
        .navigationTitle("iikb")
        .navigationSubtitle(status.summary)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            if !status.isAdded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Turn On", systemImage: "keyboard.badge.ellipsis") { HexStatus.openSettings() }
                        .buttonStyle(.borderedProminent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { MicSwitch() }
                .sharedBackgroundVisibility(.hidden)
        }
    }

    private var tryIt: some View {
        TryField(view: field)
            .overlay(alignment: .topLeading) {
                if !state.typed {
                    Text("Type something with iikb")
                        .font(.title3)
                        .foregroundStyle(Color.hexSecondary)
                        .padding(.horizontal, 19)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
    }

    private var setUp: some View {
        Box(header: "Set Up") { SetupSteps() }
    }

    /// The settings pages Home links straight to, each showing what it's set to.
    private static let shortcuts: [SettingsPage.Page] = [.dictionary, .writing, .model, .mic, .theme, .layout, .typing, .feedback]

    private static let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// What Hex has gathered, one tile per tab that keeps it.
    private var stats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            Button { Router.shared.show(.transcripts) } label: { VoiceTile() }
                .buttonStyle(CardPress())
            Button { Router.shared.show(.clipboard) } label: {
                Tile(symbol: "list.clipboard.fill", color: .orange, title: state.copied == 1 ? "item copied" : "items copied", value: state.copied.formatted())
            }
            .buttonStyle(CardPress())
            Button { Router.shared.show(.taps) } label: {
                Tile(symbol: "hand.tap.fill", color: .blue, title: state.taps == 1 ? "tap learned" : "taps learned", value: state.taps.formatted())
            }
            .buttonStyle(CardPress())
        }
    }

    private var shortcutCards: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(Self.shortcuts, id: \.self) { page in
                Button { Router.shared.show(.settings, settings: page) } label: {
                    Tile(symbol: page.glyph.0, color: page.glyph.1, title: page.title, detail: page.value)
                }
                .buttonStyle(CardPress())
                .accessibilityIdentifier("home-\(page.rawValue)")
            }
        }
    }
}

/// The microphone, on or off, as it really is: on, the keyboard starts each dictation in place, and it stays on until
/// you turn it off here; off, it goes off once what you're saying is written down. The keyboard can't turn it off.
private struct MicSwitch: View {
    @State private var flipping: Bool?
    @State private var failure: String?

    var body: some View {
        let listener = Listener.shared
        let on = flipping ?? (listener.isMicOn && !listener.isTurningMicOff)
        HStack(spacing: 8) {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
                .font(.subheadline)
                .foregroundStyle(Color.hexSecondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Toggle("Microphone", isOn: Binding(get: { on }, set: flip))
                .labelsHidden()
                .tint(.blue)
                .accessibilityIdentifier("home-mic")
        }
        .alert("Couldn’t Turn On the Microphone", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Settings") { HexStatus.openSettings() }
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

/// What you've dictated today.
private struct VoiceTile: View {
    var body: some View {
        let today = Transcripts.shared.all.prefix { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words }
        Tile(symbol: "text.bubble.fill", color: .pink, title: today == 1 ? "word said today" : "words said today", value: today.formatted())
    }
}

/// The field to try Hex in: a UITextView, so launch options can set its keyboard and return key as tests ask.
private struct TryField: UIViewRepresentable {
    let view: UITextView

    func makeUIView(context: Context) -> UITextView { view }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}
