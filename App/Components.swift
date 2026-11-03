import SwiftUI

/// How a page uses the screen it's on. Only the iPhone Duo open and held wide (951 × 669) has room for two columns,
/// as an iPad's split view does; everywhere else, the cover either way up and the open screen held tall, a page is one
/// column that scrolls as one, as iOS lays out a compact width.
enum Arrangement {
    case side, single

    static let wide: CGFloat = 800

    init(window: CGSize) {
        self = window.width >= Self.wide && window.width > window.height ? .side : .single
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

/// Two columns with a hairline between, each its own page with its own header, scrolling on its own, meeting at the
/// window's middle, which on the open Duo is the hinge. In one column they follow each other.
struct Panes<First: View, Second: View>: View {
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @Environment(\.window) private var window
    @Environment(\.arrangement) private var arrangement

    var body: some View {
        switch arrangement {
        case .side:
            GeometryReader { proxy in
                let hinge = window.width / 2 - proxy.frame(in: .global).minX
                HStack(spacing: 0) {
                    first.frame(width: max(hinge - 0.5, 0))
                    Rectangle().fill(Color.hexDivider).frame(width: 1).ignoresSafeArea(edges: .vertical)
                    second.frame(maxWidth: .infinity)
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

/// A page's name, small and at its top left, as Raycast's are.
struct PageTitle: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

/// A row of pills, the picked one filled: Raycast's tabs inside a page.
struct Pills<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    @Namespace private var pill

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(items, id: \.self) { item in
                        let picked = item == selection
                        Button {
                            withAnimation(.snappy(duration: 0.28)) { selection = item }
                        } label: {
                            Text(title(item))
                                .font(.body.weight(.medium))
                                .foregroundStyle(picked ? Color.hexPillLabel : Color.hexSecondary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 8)
                                .background {
                                    if picked { Capsule().fill(Color.hexPill).matchedGeometryEffect(id: "pill", in: pill) }
                                }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .id(item)
                        .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, item in withAnimation { reader.scrollTo(item, anchor: .center) } }
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
                    .foregroundStyle(Color.hexSecondary)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 {
                            Rectangle().fill(Color.hexDivider).frame(height: 1).padding(.leading, 20)
                        }
                    }
                }
            }
            .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Color.hexSecondary)
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
                    .foregroundStyle(Color.hexSecondary)
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
            Circle().strokeBorder(Color.hexSecondary.opacity(picked ? 0 : 0.9), lineWidth: 1.5)
            if picked {
                Circle().fill(Color.hexPill)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.hexPillLabel)
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

/// A row that opens a page, with what it holds in gray before the chevron.
struct LinkRow<Destination: View>: View {
    let title: String
    var value: String? = nil
    var symbol: (String, Color)? = nil
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                if let symbol { Glyph(symbol: symbol.0, color: symbol.1) }
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(Color.hexSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.hexSecondary)
                    .accessibilityHidden(true)
            }
            .row()
        }
        .buttonStyle(.plain)
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

/// A Raycast tile: a glyph at its top left, a title under it, a value or a line in gray.
struct Tile: View {
    let symbol: String
    let color: Color
    let title: String
    var value: String? = nil
    var detail: String? = nil
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Glyph(symbol: symbol, color: color, size: 34)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.85), in: .capsule)
                        .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 18)
            if let value {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(title)
                .font(value == nil ? .body.weight(.medium) : .subheadline)
                .foregroundStyle(value == nil ? Color.primary : Color.hexSecondary)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.hexSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
        .contentShape(.rect(cornerRadius: HexStyle.cardRadius))
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
    func hexPage() -> some View {
        background(Color.hexPage.ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// A pushed page in the app's look: its rows on the page color, a small inline title.
    func pushedPage(_ title: String) -> some View {
        hexPage()
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
