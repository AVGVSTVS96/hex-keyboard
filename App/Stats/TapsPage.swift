import Charts
import KeyboardStore
import KeyboardCore
import KeyboardUI
import SwiftUI
import notify

/// Stats' Taps: what the keyboard learned of where you tap, for one screen at a time: your numbers, the keyboard drawn
/// with it (Heat, Aim, Accuracy), a picked key up close, how each half pulls, and the keys you miss most. Wide, the
/// keyboard and the pull take the pane before the hinge and the rest the one after.
struct TapsPage: View {
    @State private var model = TapsModel()
    @State private var mode = LaunchOptions.tapsMode ?? .heat
    @Environment(\.arrangement) private var arrangement
    @Environment(\.window) private var window

    var body: some View {
        Group {
            if let board = model.board {
                content(board)
            } else {
                empty
            }
        }
        .toolbar {
            if model.layouts.count > 1 {
                ToolbarItem(placement: .topBarTrailing) { screens }
            }
        }
        .onAppear {
            model.screen = window
            model.reload()
        }
        .onChange(of: window) { _, size in model.screen = size }
    }

    @ViewBuilder private func content(_ board: TapBoard) -> some View {
        let summary = TapSummary(board)
        if arrangement == .side {
            Panes {
                ScrollViewReader { reader in
                    Column(top: 4) {
                        map(board, reader: reader)
                        Thumbs(board: board, summary: summary)
                    }
                }
            } second: {
                ScrollViewReader { reader in
                    Column(top: 4) {
                        Numbers(summary: summary)
                        detail(board)
                        Misses(summary: summary, selected: model.selected) { pick($0, reader: $1 ? reader : nil, anchor: "detail") }
                    }
                    .onAppear { scrollForLaunch(reader) }
                }
            }
        } else {
            ScrollViewReader { reader in
                Column(top: 4) {
                    Numbers(summary: summary)
                    map(board, reader: reader)
                    detail(board)
                    Thumbs(board: board, summary: summary)
                    Misses(summary: summary, selected: model.selected) { pick($0, reader: $1 ? reader : nil, anchor: "map") }
                        .id("misses")
                }
                .onAppear { scrollForLaunch(reader) }
            }
        }
    }

    private func map(_ board: TapBoard, reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionPills(sections: TapMapView.Mode.allCases, selection: $mode, title: \.title)
            MapView(board: board, revision: model.revision, mode: mode, selected: model.selected) { key in
                withAnimation(.snappy(duration: 0.25)) { model.selected = key }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Legend(mode: mode, hasSelection: model.selected != nil)
                .padding(.horizontal, 4)
        }
        .id("map")
    }

    @ViewBuilder private func detail(_ board: TapBoard) -> some View {
        if let key = model.selected, let aim = board.aims.first(where: { $0.key == key }) {
            KeyDetail(aim: aim, keys: board.keys) {
                withAnimation(.snappy(duration: 0.25)) { model.selected = nil }
            }
            .id("detail")
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    /// Picks a key, and brings it into view when picked from a row rather than dragged to on the chart.
    private func pick(_ key: Key, reader: ScrollViewProxy?, anchor: String) {
        withAnimation(.snappy(duration: 0.25)) { model.selected = key }
        guard let reader else { return }
        withAnimation(.snappy(duration: 0.35)) { reader.scrollTo(anchor, anchor: .top) }
    }

    private func scrollForLaunch(_ reader: ScrollViewProxy) {
        guard let target = LaunchOptions.tapsScroll else { return }
        Task { @MainActor in
            reader.scrollTo(target == "detail" ? "detail" : "misses", anchor: target == "detail" ? .top : .bottom)
        }
    }

    private var screens: some View {
        Menu {
            Picker("Screen", selection: $model.signature) {
                ForEach(model.layouts, id: \.signature) { layout in
                    VStack {
                        Text(model.title(of: layout.signature))
                        Text("\(layout.taps.formatted()) taps")
                    }
                    .tag(Optional(layout.signature))
                }
            }
        } label: {
            Label(model.signature.map(model.title(of:)) ?? "Screen", systemImage: "rectangle.on.rectangle")
                .labelStyle(.titleAndIcon)
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No Taps Yet", systemImage: "hand.tap")
        } description: {
            Text(AppStatus.shared.fullAccess
                ? "Type with the keyboard anywhere. Your taps show up here each time it closes."
                : "Type with the keyboard anywhere. Your taps show up here each time it closes, once Allow Full Access is on.")
        } actions: {
            if !AppStatus.shared.fullAccess {
                Button("Allow Full Access") { AppStatus.openSettings() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// The touch model the keyboard last shared, read again whenever it shares a new one and whenever the app comes forward.
@MainActor @Observable private final class TapsModel {
    private(set) var touches = TouchModel()
    private(set) var layouts: [(signature: String, taps: Int)] = []
    private(set) var board: TapBoard?
    private(set) var revision = 0
    var selected: Key? = nil
    @ObservationIgnored private var launchKey = LaunchOptions.tapsKey
    var signature: String? { didSet { if signature != oldValue { rebuild() } } }
    var screen = CGSize.zero { didSet { if screen != oldValue { reload() } } }
    @ObservationIgnored private var token: Int32 = 0

    init() {
        token = MemoryStore.observeTouches { [weak self] in self?.reload() }
        NotificationCenter.default.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    isolated deinit {
        notify_cancel(token)
    }

    private var isDuo: Bool { Duo.isDuo(short: min(screen.width, screen.height)) }

    /// The letters of the screen the app is on now, whose taps show first.
    private var current: String {
        LayoutContext(device: .phone, layer: .letters, isLandscape: screen.width > screen.height, isOpen: Duo.isOpen(short: min(screen.width, screen.height))).signature
    }

    func reload() {
        guard screen != .zero else { return }
        touches = MemoryStore.sharedTouches() ?? TouchModel()
        layouts = touches.signatures.filter { LayoutContext(signature: $0.signature) != nil }
        let kept = signature.flatMap { name in layouts.contains { $0.signature == name } ? name : nil }
        let picked = kept ?? layouts.first { $0.signature == current }?.signature ?? layouts.first?.signature
        if picked == signature { rebuild() } else { signature = picked }
        if let label = launchKey, let key = board?.aims.first(where: { $0.key.label == label })?.key {
            selected = key
            launchKey = nil
        }
    }

    private func rebuild() {
        board = signature.flatMap(LayoutContext.init(signature:)).map { context in
            var context = context
            context.keySpacing = SettingsModel.shared.settings.keySpacing
            return TapBoard(touches, on: context, screen: screen)
        }
        if let key = selected, board?.aims.contains(where: { $0.key == key }) != true { selected = nil }
        revision += 1
    }

    /// The screen and hold a touch model was kept for: on the iPhone Duo, folded or open, portrait or landscape.
    func title(of signature: String) -> String {
        guard let context = LayoutContext(signature: signature) else { return signature }
        let screen = if context.device != .phone {
            "iPad, \(context.isLandscape ? "landscape" : "portrait")"
        } else if isDuo {
            Duo.Screen(open: context.isOpen, landscape: context.isLandscape).name
        } else {
            "iPhone, \(context.isLandscape ? "landscape" : "portrait")"
        }
        let layer = switch context.layer {
        case .letters: ""
        case .numbers: ", numbers"
        case .symbols: ", symbols"
        }
        let hand = switch context.oneHanded {
        case .left: ", left hand"
        case .right: ", right hand"
        case .off: ""
        }
        return screen + layer + hand + (context.isSplit ? ", split" : "")
    }
}

/// The numbers the page shows, worked out once per touch model.
private struct TapSummary {
    struct Miss {
        let key: Key
        let share: Double
        let onto: Key?
    }

    let taps: Int
    let onTarget: Double
    let lately: (share: Double, count: Int)?
    let offCenter: Double
    let halves: [(name: String, drift: (x: Double, y: Double))]
    let space: (x: Double, y: Double)?
    let misses: [Miss]

    init(_ board: TapBoard) {
        let letters = board.aims.filter { $0.key.label != " " }
        let weight = Double(max(letters.reduce(0) { $0 + $1.taps }, 1))
        taps = board.aims.reduce(0) { $0 + $1.taps }
        onTarget = letters.reduce(0.0) { $0 + Double($1.taps) * $1.onTarget } / weight
        offCenter = letters.reduce(0.0) { $0 + Double($1.taps) * hypot($1.drift.x, $1.drift.y) } / weight
        let recent = letters.flatMap { aim in aim.recent.map { $0.landed == aim.key } }
        lately = recent.isEmpty ? nil : (Double(recent.count(where: \.self)) / Double(recent.count), recent.count)

        let typed = letters.filter { $0.taps > 0 }
        let xs = typed.map(\.frame.midX)
        let middle = ((xs.max() ?? 0) + (xs.min() ?? 0)) / 2
        halves = [("Left half", typed.filter { $0.frame.midX < middle }), ("Right half", typed.filter { $0.frame.midX >= middle })].map { name, aims in
            let taps = Double(max(aims.reduce(0) { $0 + $1.taps }, 1))
            return (name, (aims.reduce(0.0) { $0 + Double($1.taps) * $1.drift.x } / taps, aims.reduce(0.0) { $0 + Double($1.taps) * $1.drift.y } / taps))
        }
        space = board.aims.first { $0.key.label == " " && $0.taps >= 10 }?.drift
        misses = letters.filter { $0.taps >= 10 }
            .map { aim in Miss(key: aim.key, share: 1 - aim.onTarget, onto: aim.landing.first { $0.key != aim.key }?.key) }
            .sorted { $0.share > $1.share }
    }

    static func describe(_ drift: (x: Double, y: Double), separator: String = ", ") -> String {
        let parts = [
            abs(drift.x) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.x), drift.x < 0 ? "left" : "right") : nil,
            abs(drift.y) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.y), drift.y < 0 ? "high" : "low") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "On center" : parts.joined(separator: separator)
    }
}

private extension TapMapView.Mode {
    static let allCases: [Self] = [.heat, .aim, .accuracy]

    var title: String {
        switch self {
        case .heat: "Heat"
        case .aim: "Aim"
        case .accuracy: "Accuracy"
        }
    }
}

enum TapColor {
    static let aim = Color.blue
    static let miss = Color(TapMapPalette.miss)
}

/// How often your letters land on the key you meant, large, over a meter of it and how your last taps compare, then
/// how many taps it's learned from and how far you aim from the keys' centers.
private struct Numbers: View {
    let summary: TapSummary

    /// How many points your last taps land on target above or below all of them, once it's a whole point.
    private var trend: Int? {
        guard let lately = summary.lately else { return nil }
        let points = Int(((lately.share - summary.onTarget) * 100).rounded())
        return points == 0 ? nil : points
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("On target")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appSecondary)
                LeadNumber(value: TapMapPalette.percent(summary.onTarget), size: 52) {
                    if let trend { TrendChip(points: trend) }
                }
            }
            Meter(share: summary.onTarget)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.appDivider).frame(height: 1)
            Figures {
                Figure(value: summary.taps.formatted(), label: summary.taps == 1 ? "tap learned" : "taps learned")
                Figure(value: String(format: "%.1f pt", summary.offCenter), label: "aim off center")
            }
        }
    }

    private var caption: String {
        let share = "Letter taps that land on the key you meant."
        guard let lately = summary.lately else { return share }
        return share + " Your last \(lately.count.formatted()): \(TapMapPalette.percent(lately.share))."
    }
}

/// A share as a thin bar, the part on target in blue and the rest in orange.
private struct Meter: View {
    let share: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 2) {
                if share >= 0.995 {
                    Capsule().fill(TapColor.aim.gradient)
                } else {
                    Capsule().fill(TapColor.aim.gradient).frame(width: max(width * share - 1, 4))
                    Capsule().fill(TapColor.miss.opacity(0.85))
                }
            }
        }
        .frame(height: 8)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}

/// How your last taps compare: green and up when they land more often, orange and down when less.
struct TrendChip: View {
    let points: Int
    var unit = " lately"

    var body: some View {
        let up = points > 0
        Text("\(up ? "+" : "−")\(abs(points))\(unit)")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(up ? Color.green : TapColor.miss)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background((up ? Color.green : TapColor.miss).opacity(0.14), in: .capsule)
            .accessibilityLabel("\(up ? "Up" : "Down") \(abs(points))\(unit)")
    }
}

/// What the map's marks mean, for the mode it's in.
private struct Legend: View {
    let mode: TapMapView.Mode
    let hasSelection: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch mode {
            case .heat:
                scale(from: "Fewer taps", to: "More") {
                    (0 ..< 24).map { Color(TapHeat.color(at: (Double($0) / 23).squareRoot(), isDark: scheme == .dark)) }
                }
            case .aim:
                HStack(spacing: 16) {
                    item(.hit, color: .blue, "Recent taps")
                    item(.memory(0), color: .blue, "Half land inside")
                    item(.aim, color: .blue, "Where you aim")
                }
            case .accuracy:
                scale(from: "1% missed", to: "25%") {
                    (0 ..< 8).map { TapColor.miss.opacity(0.12 + Double($0) / 7 * 0.73) }
                }
            }
            Text(hasSelection ? about : about + " Tap a key to see it up close.")
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(Color.appSecondary)
    }

    private var about: String {
        switch mode {
        case .heat: "Where your thumbs land most."
        case .aim: "Each key’s last taps, and where you aim for it."
        case .accuracy: hasSelection ? "Where the picked key’s taps land." : "How often each key’s taps land on another."
        }
    }

    private func scale(from start: String, to end: String, colors: () -> [Color]) -> some View {
        HStack(spacing: 10) {
            Text(start).fixedSize()
            Capsule()
                .fill(LinearGradient(colors: colors(), startPoint: .leading, endPoint: .trailing))
                .background(Capsule().fill(Color(TapMapPalette.backdrop)))
                .frame(height: 6)
            Text(end).fixedSize()
        }
    }

    private func item(_ glyph: TapGlyph, color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(uiImage: glyph.image(color: UIColor(color), surface: TapMapPalette.backdrop))
            Text(title).lineLimit(1)
        }
    }
}

private struct MapView: UIViewRepresentable {
    let board: TapBoard
    let revision: Int
    let mode: TapMapView.Mode
    let selected: Key?
    let select: (Key?) -> Void

    final class Coordinator {
        var revision = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TapMapView {
        let map = TapMapView()
        map.setContentHuggingPriority(.defaultLow, for: .horizontal)
        map.layer.borderWidth = 1
        return map
    }

    func updateUIView(_ map: TapMapView, context: Context) {
        map.layer.borderColor = AppStyle.edge.resolvedColor(with: map.traitCollection).cgColor
        map.onSelect = { select($0?.key) }
        if context.coordinator.revision != revision {
            context.coordinator.revision = revision
            map.show(board)
        }
        map.mode = mode
        map.highlight(selected)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TapMapView, context: Context) -> CGSize? {
        let width = min(proposal.width ?? board.size.width, board.size.width)
        return CGSize(width: width, height: board.size.height * width / board.size.width)
    }
}

/// A UIKit chart from KeyboardUI, as tall as its width asks.
private struct Drawing<View: UIView>: UIViewRepresentable {
    let make: () -> View
    let update: (View) -> Void
    let height: (CGFloat) -> CGFloat

    func makeUIView(context: Context) -> View {
        let view = make()
        view.translatesAutoresizingMaskIntoConstraints = true
        NSLayoutConstraint.deactivate(view.constraints)
        return view
    }

    func updateUIView(_ view: View, context: Context) { update(view) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: View, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: height(width))
    }
}

private struct Keycap: View {
    let key: Key
    var size: CGFloat = 40

    var body: some View {
        let name = TapMapPalette.name(of: key)
        Text(name)
            .font(.system(size: name.count == 1 ? size * 0.5 : size * 0.3, weight: .medium))
            .frame(width: size * (name.count == 1 ? 0.9 : 1.5), height: size)
            .background(Color.appPressed, in: .rect(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel(name)
    }
}

/// One key up close: how often it lands, where you aim, its last taps around it, where they land, and what its aim
/// follows.
private struct KeyDetail: View {
    let aim: Aim
    let keys: [(key: Key, frame: Rect)]
    let close: () -> Void

    private var name: String { TapMapPalette.name(of: aim.key) }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 24) {
                Keycap(key: aim.key, size: 56)
                Figure(value: TapMapPalette.percent(aim.onTarget), label: "on target").fixedSize()
                Figure(value: aim.taps.formatted(), label: aim.taps == 1 ? "tap" : "taps").fixedSize()
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.appSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.appPressed, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(aimed)
                .font(.subheadline)
                .foregroundStyle(Color.appSecondary)

            Drawing(make: { TapCloseUpView() }, update: { $0.show(aim, keys: keys) }, height: { _ in TapCloseUpView.height })
            if !aim.recent.isEmpty { recent }

            section("Where its taps land") { SegmentedBar(parts: landing) }
            section("Its aim follows") { MemoryBar(weights: aim.memories.map(\.weight)) }
        }
    }

    private var aimed: String {
        let drift = TapSummary.describe(aim.drift)
        return drift == "On center" ? "You aim at its center." : "You aim \(drift) of its center."
    }

    private var recent: some View {
        let hits = aim.recent.count(where: { $0.landed == aim.key })
        let strays = Dictionary(grouping: aim.recent.compactMap { $0.landed == aim.key ? nil : $0.landed }, by: \.self)
            .sorted { $0.value.count > $1.value.count }
            .map { "\(TapMapPalette.name(of: $0.key)) \($0.value.count)" }
        return HStack(spacing: 16) {
            dot(TapColor.aim, "\(hits) of the last \(aim.recent.count) on \(name)")
            if !strays.isEmpty { dot(TapColor.miss, strays.joined(separator: ", ")) }
        }
        .font(.footnote)
        .foregroundStyle(Color.appSecondary)
    }

    private func dot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color.opacity(0.85)).frame(width: 7, height: 7)
            Text(text)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, 4)
    }

    /// The key itself in blue, its three biggest misses in orange, and the rest as one in gray.
    private var landing: [SegmentedBar.Part] {
        let misses = aim.landing.filter { $0.key != aim.key }
        var parts = [SegmentedBar.Part(name: name, share: aim.onTarget, color: TapColor.aim)]
        parts += misses.prefix(3).filter { $0.share >= 0.005 }.map { SegmentedBar.Part(name: TapMapPalette.name(of: $0.key), share: $0.share, color: TapColor.miss) }
        let rest = 1 - parts.reduce(0) { $0 + $1.share }
        if rest >= 0.005 { parts.append(SegmentedBar.Part(name: "other", share: rest, color: Color.appSecondary.opacity(0.45))) }
        return parts
    }
}

/// How much a key's aim leans on all its taps, about its last 30 and about its last 3, in one thin bar.
private struct MemoryBar: View {
    let weights: [Double]
    private static let names = ["All taps", "Last 30", "Last 3"]
    private static let strengths = [0.9, 0.5, 0.22]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width - 2 * CGFloat(weights.count - 1)
                HStack(spacing: 2) {
                    ForEach(weights.indices, id: \.self) { index in
                        Capsule().fill(Color.primary.opacity(Self.strengths[index])).frame(width: max(width * weights[index], 4))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                ForEach(weights.indices, id: \.self) { index in
                    HStack(spacing: 5) {
                        MemoryMark(index: index)
                        Text("\(Self.names[index]) \(TapMapPalette.percent(weights[index]))").monospacedDigit()
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.appSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weights.indices.map { "\(Self.names[$0]) \(TapMapPalette.percent(weights[$0]))" }.joined(separator: ", "))
    }
}

/// The close-up's mark for one of a key's three memories, drawn as it draws them.
private struct MemoryMark: View {
    let index: Int

    var body: some View {
        Group {
            if index < 2 {
                Circle().strokeBorder(Color.primary, lineWidth: 1.75).frame(width: index == 0 ? 13.5 : 9.5)
            } else {
                Circle().fill(Color.primary).frame(width: 5)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// Every key's pull as an arrow, then where each half of the keyboard and the space bar aim, each on a small target.
private struct Thumbs: View {
    let board: TapBoard
    let summary: TapSummary

    var body: some View {
        Card(header: "How your thumbs pull", footer: "Each arrow runs from a key’s center to where you aim for it, drawn \(Int(TapPullView.magnification))× as long.") {
            Drawing(make: { TapPullView() }, update: { $0.show(board.aims, keys: board.keys, size: board.size) }) { width in
                board.size.height * min(1, width / board.size.width)
            }
            let targets = summary.halves + (summary.space.map { [("Space bar", $0)] } ?? [])
            let reach = max(2.5, targets.map { hypot($0.drift.x, $0.drift.y) }.max() ?? 0)
            HStack(alignment: .top, spacing: 12) {
                ForEach(targets.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        Target(drift: targets[index].drift, reach: reach)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TapSummary.describe(targets[index].drift, separator: "\n"))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text(targets[index].name)
                                .font(.footnote)
                                .foregroundStyle(Color.appSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Where a part of the keyboard aims against its keys' centers: a crosshair, a ring each point, and the aim.
private struct Target: View {
    let drift: (x: Double, y: Double)
    let reach: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: radius, y: size.height / 2)
            let scale = (radius - 7) / reach
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color(TapMapPalette.backdrop)))
            for ring in [reach / 2, reach] {
                let r = ring * scale
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(Color.appSecondary.opacity(0.22)), lineWidth: 1)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(cross, with: .color(Color.appSecondary.opacity(0.3)), lineWidth: 1)
            let point = CGPoint(x: center.x + drift.x * scale, y: center.y + drift.y * scale)
            var line = Path()
            line.move(to: center)
            line.addLine(to: point)
            context.stroke(line, with: .color(TapColor.aim), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(Color.appCard))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)), with: .color(TapColor.aim))
        }
        .frame(width: 76, height: 76)
        .accessibilityHidden(true)
    }
}

/// The share of each letter's taps that land on another key, most missed first, and where the worst three go.
private struct Misses: View {
    let summary: TapSummary
    let selected: Key?
    let pick: (Key, _ scrolls: Bool) -> Void
    @State private var hovered: String?

    private var shown: [TapSummary.Miss] { summary.misses.filter { $0.share >= 0.005 } }

    var body: some View {
        if !shown.isEmpty {
            Card(header: "Misses by key", footer: "Each letter’s taps that land on another key, most missed first.") {
                chart
                VStack(spacing: 0) {
                    ForEach(shown.prefix(3), id: \.key) { miss in
                        row(miss)
                        if miss.key != shown.prefix(3).last?.key { Rectangle().fill(Color.appDivider).frame(height: 1) }
                    }
                }
            }
        }
    }

    private var chart: some View {
        let peak = max(shown.first?.share ?? 0, 0.05)
        let typical = 1 - summary.onTarget
        return Chart {
            ForEach(shown, id: \.key) { miss in
                BarMark(x: .value("Key", TapMapPalette.name(of: miss.key)), y: .value("Missed", miss.share), width: .ratio(0.62))
                    .foregroundStyle(TapColor.miss.opacity(selected == nil || selected == miss.key ? 0.9 : 0.3).gradient)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous))
            }
            RuleMark(y: .value("All letters", typical))
                .foregroundStyle(Color.appSecondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("all letters \(TapMapPalette.percent(typical))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.appSecondary)
                }
        }
        .chartYScale(domain: 0 ... max(peak, typical * 1.4))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.appDivider)
                AxisValueLabel {
                    if let share = value.as(Double.self) { Text(TapMapPalette.percent(share)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption.weight(.medium)) }
        }
        .chartXSelection(value: $hovered)
        .onChange(of: hovered) { _, name in
            if let name, let miss = shown.first(where: { TapMapPalette.name(of: $0.key) == name }) { pick(miss.key, false) }
        }
        .frame(height: 132)
        .accessibilityLabel("Misses by key")
    }

    private func row(_ miss: TapSummary.Miss) -> some View {
        Button { pick(miss.key, true) } label: {
            HStack(spacing: 12) {
                Keycap(key: miss.key, size: 34)
                if let onto = miss.onto {
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                    Keycap(key: onto, size: 34).opacity(0.75)
                }
                Spacer()
                Text(TapMapPalette.percent(miss.share))
                    .font(.display(20))
                    .monospacedDigit()
                Text("missed")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(CardPress())
        .accessibilityLabel("\(TapMapPalette.name(of: miss.key)), \(TapMapPalette.percent(miss.share)) missed\(miss.onto.map { ", mostly onto \(TapMapPalette.name(of: $0))" } ?? "")")
    }
}
