import KeyboardCore
import KeyboardUI
import Charts
import SwiftUI

/// Everything about voice typing in one tab: every dictation, newest first by day, with how much and how fast you
/// talk, and the settings for how Hex writes what you say. Wide, the picked transcript, or the settings, take the pane
/// past the hinge.
struct VoicePage: View {
    enum Tab: String, CaseIterable, Hashable {
        case transcripts, settings

        var title: String {
            switch self {
            case .transcripts: "Transcripts"
            case .settings: "Settings"
            }
        }
    }

    private let store = Transcripts.shared
    @Bindable private var router = Router.shared
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
                        Group {
                            if router.voicePage == .transcripts { list } else { usage }
                        }
                        .safeAreaBar(edge: .top) { header }
                    } second: {
                        if router.voicePage == .settings {
                            Column(top: 12) { VoiceSettings() }
                        } else if let transcript = store.all.first(where: { $0.id == (selected ?? store.all.first?.id) }) {
                            TranscriptDetail(transcript: transcript, beside: true)
                        } else {
                            empty
                        }
                    }
                } else {
                    Group {
                        if router.voicePage == .transcripts { list } else { Column(top: 4) { VoiceSettings() } }
                    }
                    .safeAreaBar(edge: .top) { header }
                }
            }
            .hexPage()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Transcript.ID.self) { id in
                if let transcript = store.all.first(where: { $0.id == id }) { TranscriptDetail(transcript: transcript, beside: false) }
            }
            .confirmationDialog("Delete all \(store.all.count) transcripts from this iPhone?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.delete(Set(store.all.map(\.id))) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(title: "Voice", trailing: store.all.isEmpty ? nil : AnyView(
                Menu {
                    Button("Delete All Transcripts", systemImage: "trash", role: .destructive) { confirmsDeleteAll = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.hexCard, in: .circle)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("More")
            ))
            Pills(items: Tab.allCases, selection: $router.voicePage, title: \.title)
                .padding(.horizontal, -4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Beside the settings: how much you've dictated, and which model writes it.
    private var usage: some View {
        Column(top: 4) {
            if !store.all.isEmpty { Summary(transcripts: store.all) }
            Box(header: "Writing Now") {
                Fact(title: VoiceModel.shared.model.title, value: VoiceModel.shared.status)
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

    private static func title(of day: Date) -> String {
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
            Text(transcript.text)
                .lineLimit(3)
                .foregroundStyle(transcript.typed ? Color.primary : Color.hexSecondary)
            HStack(spacing: 6) {
                Text(transcript.date, format: .dateTime.hour().minute())
                Text("·")
                Text(Duration.seconds(transcript.seconds), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
                if !transcript.typed {
                    Text("·")
                    Text("Canceled, not typed")
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
            Text(transcript.text)
                .font(.title3)
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
                Fact(title: "Typed", value: transcript.typed ? "Yes" : "No, you canceled it")
                if let model = transcript.model { Fact(title: "Written by", value: model) }
            }
            RecordingSection(transcript: transcript)
            Box {
                ActionRow(title: "Delete Transcript", role: .destructive) { confirmsDelete = true }
            }
        }
        .hexPage()
        .navigationTitle(beside ? "" : "Transcript")
        .navigationBarTitleDisplayMode(.inline)
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

/// How Hex writes what you say: the model, the words and punctuation it types, your vocabulary, and how long the mic
/// stays on.
struct VoiceSettings: View {
    private let model = SettingsModel.shared
    private let voice = VoiceModel.shared

    var body: some View {
        Box(header: "Model", footer: "What you say is written on this iPhone and never leaves it. Until the model you pick is ready, Apple’s writes.") {
            ForEach(VoiceModel.Model.allCases, id: \.self) { choice in
                ChoiceRow(title: choice.title, detail: choice.detail, picked: choice == voice.model) {
                    voice.pick(choice)
                } extra: {
                    if choice == voice.model, voice.state != .ready { progress }
                }
            }
        }
        Box(header: "Writing", footer: "Capitals follow Auto-Capitalization in Keyboard › Typing, as your typing’s do. Transcripts keep what the model wrote.") {
            ToggleRow(title: "Um and Uh", detail: "Types them as you say them.", isOn: model.umAndUh)
            ForEach(DictationStyle.allCases, id: \.self) { style in
                ChoiceRow(title: style.title, detail: style.detail, picked: model.dictationStyle == style) { model.dictationStyle(style) }
            }
        }
        Box(header: "Vocabulary", footer: "The words the voice model gets wrong, each with what it writes instead.") {
            LinkRow(title: "Your Words", value: VoiceVocabulary.shared.vocabulary.terms.count.formatted(), symbol: ("character.book.closed.fill", .orange)) {
                VocabularyView()
            }
        }
        Box(header: "Keep Mic On", footer: "After you dictate, Hex keeps the mic on this long, so the mic beside the suggestions starts and stops without leaving your app. Hold it to turn the mic off.") {
            ForEach(Dictation.micChoices, id: \.self) { seconds in
                ChoiceRow(title: Dictation.title(keepingMicOn: seconds), picked: model.keepMicOn == seconds) { model.keepMicOn(seconds) }
            }
        }
    }

    @ViewBuilder private var progress: some View {
        switch voice.state {
        case .downloading(let done):
            ProgressView(value: done) {
                Text("Downloading, \(done.formatted(.percent.precision(.fractionLength(0))))")
            }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
            .padding(.top, 8)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Getting ready")
            }
            .font(.footnote)
            .foregroundStyle(Color.hexSecondary)
            .padding(.top, 8)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn’t get it ready: \(reason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Try Again") { voice.retry() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.top, 8)
        case .ready:
            EmptyView()
        }
    }
}
