import KeyboardCore
import KeyboardUI
import Charts
import SwiftUI

/// Every dictation, newest first by day, under how much and how fast you talk. Wide, the picked transcript takes the
/// second pane; elsewhere it opens on its own.
struct TranscriptsPage: View {
    private let store = Transcripts.shared
    @State private var query = ""
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
            .appPage()
            .navigationTitle("Transcripts")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { MicSwitchItem() }
            .navigationDestination(for: Transcript.ID.self) { id in
                if let transcript = store.all.first(where: { $0.id == id }) {
                    TranscriptDetail(transcript: transcript, beside: false)
                        .navigationTitle("Transcript")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { MicSwitchItem() }
                }
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
        .background(picked ? Color.appPressed : .clear)
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

private struct Row: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(transcript.shown)
                .lineLimit(3)
                .foregroundStyle(transcript.typed && !transcript.text.isEmpty ? Color.primary : Color.appSecondary)
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
            .foregroundStyle(Color.appSecondary)
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

/// How much you've dictated, in dictation's pink: every word said, how this week compares with the one before, words a
/// day for the last two weeks with the best day marked, then time talking, pace and today. A tap opens Stats ›
/// Dictation.
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

    /// How many percent more or fewer words the last seven days hold than the seven before, once both have some.
    private func trend(_ days: [Day]) -> Int? {
        let before = days.prefix(7).reduce(0) { $0 + $1.words }, lately = days.suffix(7).reduce(0) { $0 + $1.words }
        guard before > 0, lately > 0 else { return nil }
        let change = Int((Double(lately - before) / Double(before) * 100).rounded())
        return change == 0 ? nil : change
    }

    var body: some View {
        let days = fortnight
        let today = days.last?.words ?? 0
        Button { Router.shared.show(StatsPage.Section.dictation) } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Glyph(symbol: "waveform", color: .pink, size: 26)
                    Text("Dictation")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appSecondary)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("Stats")
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appSecondary)
                }
                LeadNumber(value: words.formatted(), size: 44) {
                    Text(words == 1 ? "word said" : "words said")
                        .font(.subheadline)
                        .foregroundStyle(Color.appSecondary)
                        .lineLimit(1)
                    if let trend = trend(days) { TrendChip(points: trend, unit: "% this week") }
                }
                FortnightChart(days: days.map { ($0.date, $0.words) })
                Rectangle().fill(Color.appDivider).frame(height: 1)
                Figures(size: 22) {
                    Figure(value: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)), label: "talking")
                    Figure(value: seconds >= 1 ? "\(Int((Double(words) / seconds * 60).rounded())) wpm" : "–", label: "pace")
                    Figure(value: today.formatted(), label: "today")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
            .contentShape(.rect(cornerRadius: AppStyle.cardRadius))
        }
        .buttonStyle(CardPress())
        .accessibilityHint("Opens Stats")
    }
}

/// Words a day for two weeks in pink, today full and the rest softer, the best day's count over its column and a dashed
/// line at the average of the days you talked.
private struct FortnightChart: View {
    let days: [(date: Date, words: Int)]

    var body: some View {
        let active = days.filter { $0.words > 0 }
        let average = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.words } / active.count
        let best = days.max { $0.words < $1.words }
        Chart {
            ForEach(days, id: \.date) { day in
                let strength = Calendar.current.isDateInToday(day.date) || day.date == best?.date ? 1.0 : 0.45
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words), width: .ratio(0.64))
                    .foregroundStyle(LinearGradient(colors: [.pink.opacity(strength), .purple.opacity(strength)], startPoint: .top, endPoint: .bottom))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous))
                    .annotation(position: .top, spacing: 4) {
                        if day.date == best?.date, day.words > 0 {
                            Text(day.words.formatted(.number.notation(.compactName)))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.pink)
                        }
                    }
            }
            if active.count > 1 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.appSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("avg \(average.formatted(.number.notation(.compactName)))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.appSecondary)
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .frame(height: 112)
        .accessibilityLabel("Words a day, last 2 weeks")
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
                    .foregroundStyle(Color.appSecondary)
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
                .foregroundStyle(transcript.text.isEmpty ? Color.appSecondary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
            Box {
                Fact(title: "Length", value: Duration.seconds(transcript.seconds).formatted(.time(pattern: .minuteSecond)))
                Fact(title: "Words", value: transcript.words.formatted())
                if transcript.seconds >= 1 {
                    Fact(title: "Pace", value: "\(Int((Double(transcript.words) / transcript.seconds * 60).rounded())) wpm")
                }
                Fact(title: "Typed", value: transcript.typed ? transcript.app.map { "In \(AppName.of($0))" } ?? "Yes" : transcript.recovered == true ? "No, iikb closed during it" : "No")
                if let model = transcript.model { Fact(title: "Written by", value: model) }
            }
            if let replaced = transcript.replaced {
                Box(header: "First Written") {
                    RowText(title: replaced.text.isEmpty ? "Nothing heard" : replaced.text, detail: replaced.model.map { "Written by \($0)" })
                        .textSelection(.enabled)
                        .row()
                }
            }
            RecordingSection(transcript: transcript)
            Box {
                ActionRow(title: "Delete Transcript", role: .destructive) { confirmsDelete = true }
            }
        }
        .appPage()
        .confirmationDialog("Delete this transcript?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Transcripts.shared.delete([transcript.id])
                if !beside { dismiss() }
            }
        }
    }
}
