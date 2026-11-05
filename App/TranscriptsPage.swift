import KeyboardCore
import KeyboardUI
import Charts
import SwiftUI

/// Every dictation, newest first by day, under how much and how fast you talk. Wide, the picked transcript takes the
/// second pane; elsewhere it opens on its own.
struct TranscriptsPage: View {
    private let store = Transcripts.shared
    @State private var query = ""
    @State private var confirmsDeleteAll = false
    @State private var selected: Transcript.ID?
    @Environment(\.arrangement) private var arrangement

    private var shown: [Transcript] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? store.all : store.all.filter { $0.text.localizedStandardContains(query) }
    }

    private var days: [(day: Date, transcripts: [Transcript])] {
        let calendar = Calendar.current
        var days: [(day: Date, transcripts: [Transcript])] = []
        for transcript in shown {
            let day = calendar.startOfDay(for: transcript.date)
            if days.last?.day == day { days[days.count - 1].transcripts.append(transcript) } else { days.append((day, [transcript])) }
        }
        return days
    }

    private var beside: Bool { arrangement == .side }

    var body: some View {
        NavigationStack {
            Group {
                if beside {
                    Panes {
                        list
                    } second: {
                        if let transcript = store.all.first(where: { $0.id == (selected ?? store.all.first?.id) }) {
                            TranscriptDetail(transcript: transcript, beside: true)
                        } else {
                            empty
                        }
                    }
                } else {
                    list
                }
            }
            .hexPage()
            .navigationTitle("Transcripts")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                if !store.all.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Delete All Transcripts", systemImage: "trash", role: .destructive) { confirmsDeleteAll = true }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                    }
                }
                MicSwitchItem()
            }
            .navigationDestination(for: Transcript.ID.self) { id in
                if let transcript = store.all.first(where: { $0.id == id }) {
                    TranscriptDetail(transcript: transcript, beside: false)
                        .navigationTitle("Transcript")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { MicSwitchItem() }
                }
            }
            .confirmationDialog("Delete all \(store.all.count) transcripts from this iPhone?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.delete(Set(store.all.map(\.id))) }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if store.all.isEmpty {
                    empty.frame(minHeight: 360)
                } else {
                    SearchField(text: $query)
                    if query.isEmpty { Summary(transcripts: store.all) }
                    if shown.isEmpty { ContentUnavailableView.search(text: query) }
                    ForEach(days, id: \.day) { day in
                        Box(header: Self.title(of: day.day)) {
                            ForEach(day.transcripts) { transcript in
                                row(transcript)
                            }
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

    @ViewBuilder private func row(_ transcript: Transcript) -> some View {
        let picked = beside && transcript.id == (selected ?? store.all.first?.id)
        Group {
            if beside {
                Button { selected = transcript.id } label: { Row(transcript: transcript) }
            } else {
                NavigationLink(value: transcript.id) { Row(transcript: transcript) }
            }
        }
        .buttonStyle(.plain)
        .background(picked ? Color.hexPressed : .clear)
        .contextMenu { Actions(transcript: transcript) }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No Transcripts", systemImage: "waveform")
        } description: {
            Text("Tap the mic at the right end of the keyboard’s suggestions and talk. Everything you dictate is kept here, on this iPhone.")
        }
    }

    static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: .now).day, days < 7 { return day.formatted(.dateTime.weekday(.wide)) }
        let thisYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return thisYear ? day.formatted(.dateTime.weekday(.wide).month(.wide).day()) : day.formatted(date: .long, time: .omitted)
    }
}

/// Raycast's search field: a magnifier and the query in a rounded card.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.hexSecondary)
            TextField("Search", text: $text)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.hexSecondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.hexCard, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.hexEdge))
    }
}

private struct Row: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(transcript.shown)
                .lineLimit(3)
                .foregroundStyle(transcript.typed && !transcript.text.isEmpty ? Color.primary : Color.hexSecondary)
            HStack(spacing: 6) {
                Text(transcript.date, format: .dateTime.hour().minute())
                Text("·")
                Text(Duration.seconds(transcript.seconds), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                if transcript.typed, let app = transcript.app {
                    Text("·")
                    Text(AppName.of(app)).lineLimit(1)
                }
                if !transcript.typed {
                    Text("·")
                    Text(transcript.recovered == true ? "Recovered" : "Not typed")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .row()
    }
}

private struct Actions: View {
    let transcript: Transcript

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = transcript.text }
        ShareLink(item: transcript.text)
        Button("Delete", systemImage: "trash", role: .destructive) { Transcripts.shared.delete([transcript.id]) }
    }
}

/// How much you've dictated: words, time talking and pace overall, and words per day for the last two weeks.
private struct Summary: View {
    let transcripts: [Transcript]

    private struct Day: Identifiable {
        var date: Date
        var words: Int
        var id: Date { date }
    }

    private var words: Int { transcripts.reduce(0) { $0 + $1.words } }
    private var seconds: Double { transcripts.reduce(0) { $0 + $1.seconds } }

    private var fortnight: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var words: [Date: Int] = [:]
        for transcript in transcripts { words[calendar.startOfDay(for: transcript.date), default: 0] += transcript.words }
        return (0 ..< 14).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map { Day(date: $0, words: words[$0] ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Stat(title: "Words", value: words.formatted())
                Stat(title: "Talking", value: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)))
                Stat(title: "Pace", value: seconds >= 1 ? "\(Int((Double(words) / seconds * 60).rounded())) wpm" : "–")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Words a day, last 2 weeks")
                    .font(.footnote)
                    .foregroundStyle(Color.hexSecondary)
                Chart(fortnight) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words), width: .ratio(0.62))
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.primary : Color.hexSecondary.opacity(0.55))
                        .clipShape(.rect(cornerRadius: 3))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(20)
        .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.footnote)
                .foregroundStyle(Color.hexSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct TranscriptDetail: View {
    let transcript: Transcript
    let beside: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDelete = false

    var body: some View {
        Column(top: beside ? 12 : 8) {
            HStack {
                Text(transcript.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.hexSecondary)
                Spacer()
                Button { UIPasteboard.general.string = transcript.text } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy")
                ShareLink(item: transcript.text) { Image(systemName: "square.and.arrow.up") }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            Text(transcript.shown)
                .font(.title3)
                .foregroundStyle(transcript.text.isEmpty ? Color.hexSecondary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.hexCard, in: .rect(cornerRadius: HexStyle.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HexStyle.cardRadius, style: .continuous).strokeBorder(Color.hexEdge))
            Box {
                Fact(title: "Length", value: Duration.seconds(transcript.seconds).formatted(.time(pattern: .minuteSecond)))
                Fact(title: "Words", value: transcript.words.formatted())
                if transcript.seconds >= 1 {
                    Fact(title: "Pace", value: "\(Int((Double(transcript.words) / transcript.seconds * 60).rounded())) wpm")
                }
                Fact(title: "Typed", value: transcript.typed ? transcript.app.map { "In \(AppName.of($0))" } ?? "Yes" : transcript.recovered == true ? "No, iikb closed during it" : "No")
                if let model = transcript.model { Fact(title: "Written by", value: model) }
            }
            RecordingSection(transcript: transcript)
            Box {
                ActionRow(title: "Delete Transcript", role: .destructive) { confirmsDelete = true }
            }
        }
        .hexPage()
        .confirmationDialog("Delete this transcript?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Transcripts.shared.delete([transcript.id])
                if !beside { dismiss() }
            }
        }
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
            Text(value).foregroundStyle(Color.hexSecondary).multilineTextAlignment(.trailing)
        }
        .row()
        .accessibilityElement(children: .combine)
    }
}
