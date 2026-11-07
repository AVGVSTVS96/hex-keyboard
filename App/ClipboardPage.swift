import KeyboardStore
import KeyboardCore
import KeyboardUI
import SwiftUI

/// What you copied, as the keyboard's clipboard panel keeps it (`ClipboardStore`, in the App Group): pinned first, then
/// by day, newest first. A tap copies an item again; holding it pins, shares or deletes it. Wide, the item last tapped
/// shows in full in the second pane, as Transcripts' picked one does.
struct ClipboardPage: View {
    @State private var store = ClipboardStore()
    @State private var items: [ClipboardHistory.Item] = []
    @State private var query = ""
    @State private var matches: [ClipboardHistory.Item] = []
    @State private var copied: ClipboardHistory.Item.Content?
    @State private var picked: ClipboardHistory.Item.Content?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.arrangement) private var arrangement
    private let status = AppStatus.shared

    private var shown: [ClipboardHistory.Item] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? items : matches
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

    private var beside: Bool { arrangement == .side }

    /// The item shown in the second pane: the one last tapped, or the newest.
    private var shownInFull: ClipboardHistory.Item? {
        items.first { $0.content == picked } ?? items.first { !$0.pinned } ?? items.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if beside {
                    Panes(list: true) {
                        list
                    } second: {
                        if let item = shownInFull {
                            ClipDetail(item: item, copied: item.content == copied, store: store, copy: { copy(item) }, changed: refresh)
                        } else {
                            empty
                        }
                    }
                } else {
                    list
                }
            }
            .appPage()
            .navigationTitle("Clipboard")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { MicSwitchItem() }
        }
        .task(id: query) { await search() }
        .onAppear(perform: catchUp)
        .onChange(of: scenePhase) { _, phase in if phase == .active { catchUp() } }
        .sensoryFeedback(.success, trigger: copied) { _, new in new != nil }
    }

    private var list: some View {
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
    }

    /// Keeps what's on the clipboard now, as the keyboard would, once the keyboard has started the history and iOS lets
    /// iikb read the clipboard without asking.
    private func catchUp() {
        copied = nil
        store.onChange = { refresh() }
        if store.started, status.fullAccess, status.pasteAllowed { store.catchUp() } else { store.reload() }
        refresh()
    }

    private func refresh() {
        items = store.history.items
        Task { await search() }
        if let copied, !items.contains(where: { $0.content == copied }) { self.copied = nil }
    }

    private func search() async {
        let query = query
        let found = await store.matching(query.trimmingCharacters(in: .whitespaces))
        guard query == self.query else { return }
        matches = found
    }

    private var missing: String? {
        if !status.fullAccess { return "Turn on Allow Full Access, so the keyboard can keep what you copy." }
        if !status.pasteAllowed { return "Set Paste from Other Apps to Allow, so the keyboard can keep what you copy." }
        return nil
    }

    private func setup(_ text: String) -> some View {
        Box {
            Button { Router.shared.show(.settings, settings: .access) } label: {
                HStack {
                    RowText(title: "Keyboard Access", detail: text)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                }
                .row()
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ item: ClipboardHistory.Item) -> some View {
        Button { copy(item) } label: { ClipRow(item: item, copied: item.content == copied, thumbnail: { store.thumbnail($0, side: 128) }) }
            .buttonStyle(.plain)
            .background(beside && item.content == shownInFull?.content ? Color.appPressed : .clear)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { copy(item) }
                if case .text(let text) = item.content { ShareLink(item: text) }
                if case .textFile(let name, _) = item.content { ShareLink(item: store.file(name)) }
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
        case .textFile:
            Task {
                guard let text = await store.text(item.content) else { return }
                UIPasteboard.general.string = text
                store.skip(changeCount: UIPasteboard.general.changeCount)
                copied = item.content
            }
            picked = item.content
            return
        case .image(let name):
            store.copy(image: name)
        }
        copied = item.content
        picked = item.content
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Nothing Copied Yet", systemImage: "list.clipboard")
        } description: {
            Text(store.started
                ? "Everything you copy shows up here and in the keyboard’s clipboard, kept on this \(ThisDevice.name)."
                : "Type with iikb in any app, and what it keeps of what you copy shows up here.")
        }
    }
}

/// One item in full, in the second pane: all its text, or its image as big as the pane, and what holding its row offers.
private struct ClipDetail: View {
    let item: ClipboardHistory.Item
    let copied: Bool
    let store: ClipboardStore
    let copy: () -> Void
    let changed: () -> Void
    @State private var fullText: String?

    /// When it was copied, and how long all of it is, once a text kept in a file is read.
    private var detail: String {
        let time = Date(timeIntervalSince1970: item.found).formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
        let unit = SettingsModel.shared.settings.clipboardLength
        let length = fullText.map { ClipboardHistory.length(of: $0, in: unit) } ?? ClipboardHistory.length(of: item.content, in: unit)
        return length.map { "\(time) · \($0)" } ?? time
    }

    var body: some View {
        Column(top: 12) {
            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appSecondary)
                .padding(.horizontal, 4)
            Group {
                switch item.content {
                case .text(let text), .textFile(_, let text):
                    Text((fullText ?? text).trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.title3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                case .image(let name):
                    FullImage(file: store.file(name))
                }
            }
            .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .clipShape(.rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
            Box {
                ActionRow(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc", action: copy)
                if case .textFile(let name, _) = item.content { ShareLink("Share", item: store.file(name)).row() }
                if case .text(let text) = item.content {
                    ShareLink(item: text) {
                        HStack {
                            Text("Share")
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.blue)
                        .row()
                    }
                    .buttonStyle(.plain)
                }
                ActionRow(title: item.pinned ? "Unpin" : "Pin", symbol: item.pinned ? "pin.slash" : "pin") {
                    store.setPinned(!item.pinned, item.content)
                    changed()
                }
            }
            Box {
                ActionRow(title: "Delete", role: .destructive) {
                    store.remove(item.content)
                    changed()
                }
            }
        }
        .task(id: item.content) {
            fullText = nil
            let text = await store.text(item.content)
            guard !Task.isCancelled else { return }
            fullText = text
        }
    }
}

/// An image as big as the pane, decoded off the main thread.
private struct FullImage: View {
    let file: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear.aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Image")
        .task(id: file) {
            let file = file
            image = await Task.detached { ClipboardStore.thumbnail(of: file, side: 1600) }.value
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
                case .text(let text), .textFile(_, let text):
                    Text(String(text.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines))
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
                        let time = Date(timeIntervalSince1970: item.found).formatted(item.pinned ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute())
                        Text(ClipboardHistory.length(of: item.content, in: SettingsModel.shared.settings.clipboardLength).map { "\(time) · \($0)" } ?? time)
                            .monospacedDigit()
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .row()
    }
}
