import KeyboardStore
import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// iikb's home (docs/design.md, "The app"): whether the keyboard is on and what's left to set up, the microphone's
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
        view.backgroundColor = AppStyle.page
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

/// What the home screen reads that isn't the keyboard's status, read again whenever iikb comes forward.
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
        AppStatus.shared.refresh()
        taps = MemoryStore.sharedTouches()?.signatures.reduce(0) { $0 + $1.taps } ?? 0
        clipboard.reload()
    }
}

/// Wide, the field and what iikb has gathered take the first half and the settings' cards the second, so the field
/// stays above the keys while you try them; elsewhere, one column.
struct HomeView: View {
    let state: HomeState
    let field: UITextView
    private let status = AppStatus.shared
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
        .appPage()
        .navigationTitle("iikb")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { MicSwitchItem() }
    }

    private var tryIt: some View {
        TryField(view: field)
            .overlay(alignment: .topLeading) {
                if !state.typed {
                    Text("Type something with iikb")
                        .font(.title3)
                        .foregroundStyle(Color.appSecondary)
                        .padding(.horizontal, 19)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
    }

    private var setUp: some View {
        Box(header: "Set Up") { SetupSteps() }
    }

    /// The settings pages Home links straight to, each showing what it's set to.
    private static let shortcuts: [SettingsPage.Page] = [.dictionary, .writing, .model, .mic, .theme, .layout, .typing, .feedback]

    private static let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// What iikb has gathered, in one card inset as the tiles under it are: a count for each tab that keeps it, opening
    /// that tab. Three across while every count fits at full size, then smaller, then a row each, so a count never runs
    /// out of its card.
    private var stats: some View {
        let today = Transcripts.shared.all.prefix { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words }
        let counts = [
            Count(symbol: "text.bubble.fill", color: .pink, value: today, label: "said today", title: today == 1 ? "Word said today" : "Words said today", open: { Router.shared.show(.transcripts) }),
            Count(symbol: "list.clipboard.fill", color: .orange, value: state.copied, label: "copied", title: state.copied == 1 ? "Item copied" : "Items copied", open: { Router.shared.show(.clipboard) }),
            Count(symbol: "hand.tap.fill", color: .blue, value: state.taps, label: state.taps == 1 ? "tap learned" : "taps learned", title: state.taps == 1 ? "Tap learned" : "Taps learned", open: { Router.shared.show(StatsPage.Section.taps) }),
        ]
        return ViewThatFits(in: .horizontal) {
            CountColumns(counts: counts, size: 28)
            CountColumns(counts: counts, size: 24)
            Box {
                ForEach(counts) { count in
                    CountButton(count: count) { CountRow(count: count) }
                }
            }
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

/// One of Home's counts, opening the tab that keeps it.
private struct Count: Identifiable {
    let symbol: String
    let color: Color
    let value: Int
    /// What it counts under the number, three across, and beside it, in a row.
    let label: String
    let title: String
    let open: () -> Void

    var id: String { symbol }
}

private struct CountButton<Label: View>: View {
    let count: Count
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: count.open) {
            label.contentShape(.rect).accessibilityElement(children: .combine)
        }
        .buttonStyle(CardPress())
    }
}

/// The counts three across in one card, split by hairlines.
private struct CountColumns: View {
    let counts: [Count]
    let size: CGFloat

    var body: some View {
        EqualColumns {
            ForEach(counts) { count in
                CountButton(count: count) {
                    VStack(alignment: .leading, spacing: 14) {
                        Glyph(symbol: count.symbol, color: count.color, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            SlotText(count.value.formatted(), shrink: 1)
                                .font(.display(size))
                                .tracking(-0.02 * size)
                            Text(count.label)
                                .font(.subheadline)
                                .foregroundStyle(Color.appSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .overlay(alignment: .leading) {
                    if count.id != counts.first?.id {
                        Rectangle().fill(Color.appDivider).frame(width: 1).padding(.vertical, 18)
                    }
                }
            }
        }
        .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
    }
}

/// A count as a row: its glyph and what it counts, the number at the right.
private struct CountRow: View {
    let count: Count

    var body: some View {
        HStack(spacing: 14) {
            Glyph(symbol: count.symbol, color: count.color, size: 28)
            Text(count.title).lineLimit(1)
            Spacer(minLength: 12)
            SlotText(count.value.formatted())
                .font(.display(22))
                .tracking(-0.02 * 22)
                .layoutPriority(1)
        }
        .row()
    }
}

/// The field to try iikb in: a UITextView, so launch options can set its keyboard and return key as tests ask.
private struct TryField: UIViewRepresentable {
    let view: UITextView

    func makeUIView(context: Context) -> UITextView { view }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}
