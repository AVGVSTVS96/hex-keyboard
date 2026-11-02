import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// Hex's home (docs/design.md, "The app"): whether the keyboard is on, a field to try it, what voice and your taps have
/// gathered, and the way to its settings.
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
        navigationController?.setNavigationBarHidden(true, animated: animated)
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
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

    func showSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: false)
    }

    private func go(to destination: HomeView.Destination) {
        switch destination {
        case .settings: navigationController?.pushViewController(SettingsViewController(), animated: true)
        case .systemSettings: UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        case .transcripts, .taps:
            guard let tabs = tabBarController else { return }
            tabs.selectedTab = tabs.tab(forIdentifier: destination == .taps ? "taps" : "transcripts")
        }
    }
}

/// What the home screen reads from the rest of the app and the keyboard, read again whenever Hex comes forward.
@Observable final class HomeState {
    var isAdded = false
    var fullAccess = false
    var taps = 0
    var typed = false

    func refresh() {
        isAdded = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? []).contains("com.shahidy.hexkeyboard.keyboard")
        fullAccess = SettingsStore.fullAccessSeen
        taps = MemoryStore.sharedTouches()?.signatures.reduce(0) { $0 + $1.taps } ?? 0
    }
}

struct HomeView: View {
    enum Destination { case settings, systemSettings, transcripts, taps }

    let state: HomeState
    let field: UITextView
    let open: (Destination) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                section("Try It") {
                    TryField(view: field)
                        .frame(height: 132)
                        .overlay(alignment: .topLeading) {
                            if !state.typed {
                                Text("Type something with Hex")
                                    .foregroundStyle(Color.hexSecondary)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    VoiceTile { open(.transcripts) }
                    TapsTile(taps: state.taps, fullAccess: state.fullAccess) { open(.taps) }
                }
                section("Set Up") {
                    Card {
                        VStack(spacing: 0) {
                            Step(done: state.isAdded, title: "Add Hex", detail: state.isAdded ? "Hex is one of your keyboards." : "Settings › Apps › Hex › Keyboards") { open(.systemSettings) }
                            Divider().overlay(Color(HexStyle.divider))
                            Step(done: state.fullAccess, title: "Allow Full Access", detail: "For voice typing, haptics, GIFs and your taps.") { open(.systemSettings) }
                            Divider().overlay(Color(HexStyle.divider))
                            Step(done: nil, title: "Paste from Other Apps", detail: "Set it to Allow, for the clipboard panel.") { open(.systemSettings) }
                        }
                    }
                }
                Button { open(.settings) } label: {
                    Card {
                        HStack(spacing: 14) {
                            Glyph(symbol: "keyboard", color: .gray)
                            Text("Keyboard Settings")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.hexSecondary)
                        }
                    }
                }
                .buttonStyle(KeyPress())
                Text("Hex only goes online to download its voice model once, search GIFs and reach the sources you add. What you type, say and copy stays on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Color.hexSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 680)
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
                        .fill(state.isAdded ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(state.isAdded ? (state.fullAccess ? "On, with Full Access" : "On") : "Not added yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.hexSecondary)
                }
            }
            Spacer()
            if !state.isAdded {
                Button("Turn On") { open(.systemSettings) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.top, 8)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)
            content()
        }
    }
}

/// A press that looks like a key's: the card takes the pressed fill.
private struct KeyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color(HexStyle.pressed).opacity(configuration.isPressed ? 0.35 : 0).clipShape(.rect(cornerRadius: HexStyle.cardRadius, style: .continuous)))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A white SF Symbol on a colored rounded square, as Settings draws its rows.
struct Glyph: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: .rect(cornerRadius: 7.5, style: .continuous))
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
                            .lineLimit(2, reservesSpace: true)
                    }
                }
            }
        }
        .buttonStyle(KeyPress())
    }
}

/// What you've dictated today, and whether the voice model is ready to write the next.
private struct VoiceTile: View {
    let action: () -> Void

    var body: some View {
        let today = Transcripts.shared.all.prefix { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.words }
        let voice = VoiceModel.shared
        let status = switch voice.state {
        case .downloading(let done): "\(voice.model.title), downloading \(done.formatted(.percent.precision(.fractionLength(0))))"
        case .loading: "\(voice.model.title), getting ready"
        case .ready: "\(voice.model.title), ready"
        case .failed: "\(voice.model.title) failed"
        }
        Tile(symbol: "waveform", color: .red, title: "Dictated today", value: "\(today.formatted()) \(today == 1 ? "word" : "words")", caption: status, action: action)
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

private struct Step: View {
    let done: Bool?
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: done == true ? "checkmark.circle.fill" : done == false ? "circle" : "arrow.up.forward.circle")
                    .font(.title2)
                    .foregroundStyle(done == true ? Color.green : done == false ? Color.orange : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.hexSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The field to try Hex in: a UITextView, so launch options can set its keyboard and return key as tests ask.
private struct TryField: UIViewRepresentable {
    let view: UITextView

    func makeUIView(context: Context) -> UITextView { view }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}
