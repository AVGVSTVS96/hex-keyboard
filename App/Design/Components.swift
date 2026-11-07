import SwiftUI

/// How a page uses the window it's given, by its width alone, never the device or the fold: two panes once each gets
/// at least an iPhone's width (the open iPhone Duo in landscape, an iPad upright or sideways, a wide Split View or
/// Stage Manager window), else one column that scrolls as one, as iOS lays out a compact width (the Duo folded or
/// open upright, an iPad mini upright, a narrow window).
enum Arrangement {
    case side, single

    static let wide: CGFloat = 750

    init(window: CGSize) {
        self = window.width >= Self.wide ? .side : .single
    }
}

private struct WindowKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 400, height: 800)
}

extension EnvironmentValues {
    var window: CGSize {
        get { self[WindowKey.self] }
        set { self[WindowKey.self] = newValue }
    }

    var arrangement: Arrangement { Arrangement(window: window) }
}

extension View {
    /// Reads the window's size for `Panes`; each tab's root wears it.
    func readsWindow() -> some View {
        modifier(WindowReader())
    }
}

private struct WindowReader: ViewModifier {
    @State private var size = WindowKey.defaultValue

    func body(content: Content) -> some View {
        content
            .environment(\.window, size)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { size = proxy.size }
                        .onChange(of: proxy.size) { _, new in size = new }
                }
                .ignoresSafeArea()
            }
    }
}

/// Two columns, each its own page scrolling on its own, each with its own margin, so no line marks where they meet:
/// two halves, or, for a list beside the page it picked (Settings, Transcripts, Clipboard), the list half the width up
/// to 480, as wide as it reads well, and the page the rest. They follow the window's size alone, so folding the Duo a
/// little or turning an iPad changes nothing but the widths. In one column they follow each other.
struct Panes<First: View, Second: View>: View {
    var list = false
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @Environment(\.arrangement) private var arrangement

    var body: some View {
        switch arrangement {
        case .side:
            GeometryReader { proxy in
                let lead = list ? min(proxy.size.width / 2, 480) : proxy.size.width / 2
                HStack(spacing: 0) {
                    first.frame(width: lead)
                    second.frame(width: proxy.size.width - lead)
                }
            }
        case .single:
            VStack(spacing: 28) {
                first
                second
            }
        }
    }
}

/// A card of rows under a gray header and over a gray footer, rows split by inset hairlines.
struct Box<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 {
                            Rectangle().fill(Color.appDivider).frame(height: 1).padding(.leading, 20)
                        }
                    }
                }
            }
            .background(Color.appCard)
            .clipShape(.rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
        }
    }
}

/// A row's title and, under it, a line on what it does.
struct RowText: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundStyle(.primary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.appSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row's padding and height, the same for every kind of row.
struct RowFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .contentShape(.rect)
    }
}

extension View {
    func row() -> some View { modifier(RowFrame()) }
}

struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { RowText(title: title, detail: detail) }
            .tint(.blue)
            .row()
            .accessibilityLabel(title)
            .accessibilityHint(detail ?? "")
    }
}

/// Raycast's radio mark: a gray ring, or a filled circle with a check when picked.
struct Radio: View {
    let picked: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.appSecondary.opacity(picked ? 0 : 0.9), lineWidth: 1.5)
            if picked {
                Circle().fill(Color.appPill)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.appPillLabel)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.snappy(duration: 0.2), value: picked)
        .accessibilityHidden(true)
    }
}

/// One of a setting's values, with the radio mark at its right.
struct ChoiceRow<Extra: View>: View {
    let title: String
    var detail: String? = nil
    let picked: Bool
    let pick: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        Button(action: pick) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    RowText(title: title, detail: detail)
                    extra
                }
                Radio(picked: picked)
            }
            .row()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
    }
}

extension ChoiceRow where Extra == EmptyView {
    init(title: String, detail: String? = nil, picked: Bool, pick: @escaping () -> Void) {
        self.init(title: title, detail: detail, picked: picked, pick: pick) { EmptyView() }
    }
}

/// A row that does something, in the accent or, for what can't be undone, red.
struct ActionRow: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                Text(title)
                Spacer()
                if let symbol { Image(systemName: symbol).font(.subheadline.weight(.semibold)) }
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.blue)
            .row()
        }
        .buttonStyle(.plain)
    }
}

/// A Raycast tile: a glyph at its top left and, right under it, a title and a line in gray, so tiles side by side
/// line up whatever their text.
struct Tile: View {
    let symbol: String
    let color: Color
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Glyph(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
        .contentShape(.rect(cornerRadius: AppStyle.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// A press that dims a card the way Raycast's do.
struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// A page's background and readable width.
extension View {
    func appPage() -> some View {
        background(Color.appPage.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// A pushed page in the app's look: its rows on the page color, a small inline title.
    func pushedPage(_ title: String) -> some View {
        appPage()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A scrolling column of boxes at the width they read best, for pages and panes.
struct Column<Content: View>: View {
    var maxWidth: CGFloat = 640
    var top: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(.horizontal, 16)
                .padding(.top, top)
                .padding(.bottom, 40)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(LaunchOptions.scrollAnchor)
    }
}

/// A card in the app's look, its content padded, under a gray header and over a gray footer.
struct Card<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        Box(header: header, footer: footer) {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A big number with its label under it, flush left, at the size its `Figures` gives it.
struct Figure: View {
    let value: String
    let label: String
    @Environment(\.figureSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SlotText(value)
                .font(.display(size))
                .tracking(-0.02 * size)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentValues {
    @Entry var figureSize: CGFloat = 30
}

/// Figures side by side in columns of one width, all at `size` while every one fits, then all smaller together, else
/// one under another, so they never shrink apart or run out of their card.
struct Figures<Content: View>: View {
    var size: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EqualColumns(spacing: 12) { content }.environment(\.figureSize, size)
            EqualColumns(spacing: 12) { content }.environment(\.figureSize, (size * 0.8).rounded())
            VStack(alignment: .leading, spacing: 12) { content }.environment(\.figureSize, (size * 0.8).rounded())
        }
    }
}

/// Columns of one width, each as wide as the widest needs, so `ViewThatFits` knows when one won't fit.
struct EqualColumns: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? (ideal.map(\.width).max() ?? 0) * CGFloat(subviews.count) + gaps
        let column = ProposedViewSize(width: (width - gaps) / CGFloat(max(subviews.count, 1)), height: nil)
        return CGSize(width: width, height: subviews.map { $0.sizeThatFits(column).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = (bounds.width - spacing * CGFloat(max(subviews.count - 1, 0))) / CGFloat(max(subviews.count, 1))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + (width + spacing) * CGFloat(index), y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

/// A card's big number and what goes beside it, on one line while all of it fits at full size, else what goes beside
/// it on a line of its own under it.
struct LeadNumber<Beside: View>: View {
    let value: String
    let size: CGFloat
    @ViewBuilder var beside: Beside

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                number
                beside
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                number
                HStack(alignment: .firstTextBaseline, spacing: 10) { beside }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var number: some View {
        SlotText(value)
            .font(.display(size))
            .tracking(-0.03 * size)
    }
}

/// Raycast's search field: a magnifier and the query in a rounded card.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.appSecondary)
            TextField("Search", text: $text)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appSecondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.appCard, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.appEdge))
    }
}

/// A fact about something, its name on the left and its value in gray on the right.
struct Fact: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Color.appSecondary).multilineTextAlignment(.trailing)
        }
        .row()
        .accessibilityElement(children: .combine)
    }
}
