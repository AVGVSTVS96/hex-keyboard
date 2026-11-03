import KeyboardCore
import KeyboardUI
import SwiftUI

/// What you copied, as the keyboard's clipboard panel keeps it (`ClipboardStore`, in the App Group): pinned first, then
/// by day, newest first. A tap copies an item again; holding it pins, shares or deletes it.
struct ClipboardPage: View {
    @State private var store = ClipboardStore()
    @State private var items: [ClipboardHistory.Item] = []
    @State private var query = ""
    @State private var copied: ClipboardHistory.Item.Content?
    @State private var confirmsClear = false
    @Environment(\.scenePhase) private var scenePhase
    private let status = HexStatus.shared

    private var shown: [ClipboardHistory.Item] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? items : store.history.matching(query)
    }

    private var groups: [(title: String, items: [ClipboardHistory.Item])] {
        let calendar = Calendar.current
        var groups: [(day: Date?, items: [ClipboardHistory.Item])] = []
        for item in shown {
            let day = item.pinned ? nil : calendar.startOfDay(for: Date(timeIntervalSince1970: item.found))
            if let last = groups.last, last.day == day { groups[groups.count - 1].items.append(item) } else { groups.append((day, [item])) }
        }
        return groups.map { ($0.day.map(TranscriptsPage.title) ?? "Pinned", $0.items) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let missing { setup(missing) }
                    if items.isEmpty {
                        empty.frame(minHeight: 360)
                    } else {
                        SearchField(text: $query)
                        if shown.isEmpty { ContentUnavailableView.search(text: query) }
                        ForEach(groups, id: \.title) { group in
                            Box(header: group.title) {
                                ForEach(group.items) { row($0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(LaunchOptions.scrollAnchor)
            .hexPage()
            .navigationTitle("Clipboard")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                if items.contains(where: { !$0.pinned }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Clear History", systemImage: "trash", role: .destructive) { confirmsClear = true }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .confirmationDialog(clearTitle, isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    store.removeUnpinned()
                    refresh()
                }
            }
        }
        .onAppear(perform: catchUp)
        .onChange(of: scenePhase) { _, phase in if phase == .active { catchUp() } }
        .sensoryFeedback(.success, trigger: copied) { _, new in new != nil }
    }

    private var clearTitle: String {
        let count = items.filter { !$0.pinned }.count
        return "Delete \(count == 1 ? "1 item" : "\(count.formatted()) items") from your clipboard history?" + (items.contains(where: \.pinned) ? " Pinned items stay." : "")
    }

    /// Keeps what's on the clipboard now, as the keyboard would, once the keyboard has started the history and iOS lets
    /// Hex read the clipboard without asking.
    private func catchUp() {
        copied = nil
        if store.started, status.fullAccess, status.pasteAllowed == true { store.catchUp() } else { store.reload() }
        refresh()
    }

    private func refresh() {
        items = store.history.items
        if let copied, !items.contains(where: { $0.content == copied }) { self.copied = nil }
    }

    private var missing: String? {
        if !status.fullAccess { return "Turn on Allow Full Access, so the keyboard can keep what you copy." }
        if status.pasteAllowed == false { return "Set Paste from Other Apps to Allow, so the keyboard can keep what you copy." }
        return nil
    }

    private func setup(_ text: String) -> some View {
        Box {
            Button { Router.shared.show(.settings, settings: .access) } label: {
                HStack {
                    RowText(title: "Keyboard Access", detail: text)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.hexSecondary)
                }
                .row()
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ item: ClipboardHistory.Item) -> some View {
        Button { copy(item) } label: { ClipRow(item: item, copied: item.content == copied, thumbnail: { store.thumbnail($0, side: 128) }) }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { copy(item) }
                if case .text(let text) = item.content { ShareLink(item: text) }
                Button(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin") {
                    store.setPinned(!item.pinned, item.content)
                    refresh()
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.remove(item.content)
                    refresh()
                }
            }
    }

    /// Puts an item back on the clipboard. It's already in the history, so the store skips it rather than keeping it again.
    private func copy(_ item: ClipboardHistory.Item) {
        switch item.content {
        case .text(let text):
            UIPasteboard.general.string = text
            store.skip(changeCount: UIPasteboard.general.changeCount)
        case .image(let name):
            store.copy(image: name)
        }
        copied = item.content
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing Copied Yet", systemImage: "list.clipboard")
        } description: {
            Text(store.started
                ? "Everything you copy shows up here and in the keyboard’s clipboard, kept on this iPhone."
                : "Open Hex keyboard in any app, and what it has kept of what you copy shows up here.")
        }
    }
}

private struct ClipRow: View {
    let item: ClipboardHistory.Item
    let copied: Bool
    let thumbnail: (String) -> UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                switch item.content {
                case .text(let text):
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .lineLimit(4)
                        .foregroundStyle(.primary)
                case .image(let name):
                    if let image = thumbnail(name) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 8, style: .continuous))
                            .accessibilityLabel("Image")
                    }
                }
                Group {
                    if copied {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        Text(Date(timeIntervalSince1970: item.found), format: item.pinned ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute())
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.hexSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.hexSecondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .row()
    }
}
