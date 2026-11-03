import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// Hex's home (docs/design.md, "The app"): whether the keyboard is on and what's left to set up, a field to try it, and
/// what voice and your taps have gathered.
final class HomeViewController: UIHostingController<HomeView> {
    private let field: UITextView
    private let state: HomeState

    init() {
        let field = UITextView(), state = HomeState()
        var open: (HomeView.Destination) -> Void = { _ in }
        self.field = field
        self.state = state
        super.init(rootView: HomeView(state: state, field: field, open: { open($0) }))
        open = { [unowned self] in go(to: $0) }
        title = "Hex"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = HexStyle.backdrop
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .clear
        field.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        field.accessibilityLabel = "Try Hex"
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

    private func go(to destination: HomeView.Destination) {
        guard let tabs = tabBarController else { return }
        tabs.selectedTab = tabs.tab(forIdentifier: destination == .taps ? "taps" : "transcripts")
    }
}

/// What the home screen reads that isn't the keyboard's status, read again whenever Hex comes forward.
@Observable final class HomeState {
    var taps = 0
    var typed = false

    func refresh() {
        HexStatus.shared.refresh()
        taps = MemoryStore.sharedTouches()?.signatures.reduce(0) { $0 + $1.taps } ?? 0
    }
}

/// On the cover, one column: status, the field, what's left to set up, then the tiles. On the open screen the field and
/// the tiles sit side by side, so the field stays in view above the keys.
struct HomeView: View {
    enum Destination { case transcripts, taps }

    let state: HomeState
    let field: UITextView
    let open: (Destination) -> Void
    private let status = HexStatus.shared
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if width == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 24) {
                            tryIt(height: 220)
                            if !status.isSetUp { setUp }
                        }
                        VStack(spacing: 16) { tiles }
                            .frame(width: 300)
                    }
                } else {
                    tryIt(height: 132)
                    if !status.isSetUp { setUp }
                    if type.isAccessibilitySize {
                        VStack(spacing: 12) { tiles }
                    } else {
                        HStack(alignment: .top, spacing: 12) { tiles }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: width == .regular ? 900 : 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.hexBackdrop)
    }

    private var header: some View {
        HStack(spacing: 16) {
            HexMark(size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hex")
                    .font(.largeTitle.bold())
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.isAdded ? (status.fullAccess ? Color.green : Color.yellow) : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(status.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.hexSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if !status.isAdded {
                Button("Turn On") { HexStatus.openSettings() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.top, 8)
    }

    private func tryIt(height: CGFloat) -> some View {
        section("Try It") {
            TryField(view: field)
                .frame(minHeight: height)
                .overlay(alignment: .topLeading) {
                    if !state.typed {
                        Text("Type something with Hex")
                            .foregroundStyle(Color.hexSecondary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
        }
    }

    private var setUp: some View {
        section("Set Up") {
            Card {
                VStack(spacing: 0) {
                    SetupSteps()
                        .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private var tiles: some View {
        VoiceTile { open(.transcripts) }
        TapsTile(taps: state.taps, fullAccess: status.fullAccess) { open(.taps) }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private struct Tile: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Glyph(symbol: symbol, color: color)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.hexSecondary)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(Color.hexSecondary)
                        Text(value)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(Color.hexSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(KeyPress())
        .accessibilityElement(children: .combine)
    }
}

/// What you've dictated today, and whether the voice model is ready to write the next.
private struct VoiceTile: View {
    let action: () -> Void

    var body: some View {
        let today = Transcripts.shared.all.prefix { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words }
        Tile(
            symbol: "waveform", color: .red, title: "Dictated today",
            value: today > 0 ? "\(today.formatted()) \(today == 1 ? "word" : "words")" : "None yet",
            caption: VoiceModel.shared.status, action: action
        )
    }
}

private struct TapsTile: View {
    let taps: Int
    let fullAccess: Bool
    let action: () -> Void

    var body: some View {
        Tile(
            symbol: "hand.tap.fill", color: .blue, title: "Your taps",
            value: taps > 0 ? taps.formatted() : "None yet",
            caption: taps > 0 ? "taps Hex learned your aim from" : fullAccess ? "Type with Hex and they show up here." : "Needs Allow Full Access.",
            action: action
        )
    }
}

/// The field to try Hex in: a UITextView, so launch options can set its keyboard and return key as tests ask.
private struct TryField: UIViewRepresentable {
    let view: UITextView

    func makeUIView(context: Context) -> UITextView { view }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}
