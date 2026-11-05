import Charts
import KeyboardUI
import SwiftUI

/// One device's typing or talking: how fast, large, with how lately compares, then words a day for the last month,
/// the hours you do it in, and what only that device knows: where your typed words came from and the apps typed in on
/// the iPhone, your dictations, or the apps you dictate into on the Mac. Wide, the speed and the month take the first
/// pane and the rest the second.
struct DeviceStats: View {
    let kind: Activity.Kind
    let activity: Activity
    let device: StatsPage.Device
    @Environment(\.arrangement) private var arrangement

    var body: some View {
        if activity.isEmpty(kind) {
            empty
        } else if arrangement == .side {
            Panes {
                Column(top: 4) {
                    Speed(kind: kind, activity: activity, device: device)
                    WordsADay(kind: kind, activity: activity)
                }
            } second: {
                Column(top: 4) { details }
            }
        } else {
            Column(top: 4) {
                Speed(kind: kind, activity: activity, device: device)
                WordsADay(kind: kind, activity: activity)
                details
            }
        }
    }

    @ViewBuilder private var details: some View {
        Hours(kind: kind, channel: activity.total(kind))
        if device == .iPhone, kind == .typed { WordSources(channel: activity.total(.typed)) }
        if device == .iPhone, kind == .said { Dictations() }
        if let apps = activity.apps[kind], !apps.isEmpty { Apps(kind: kind, apps: apps) }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(kind == .typed ? "No Typing Yet" : "No Dictation Yet", systemImage: kind == .typed ? "keyboard" : "waveform")
        } description: {
            Text(emptyText)
        } actions: {
            if device == .iPhone, kind == .typed, !AppStatus.shared.fullAccess {
                Button("Allow Full Access") { AppStatus.openSettings() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private var emptyText: String {
        switch (device, kind) {
        case (.iPhone, .typed):
            AppStatus.shared.fullAccess
                ? "Type with the keyboard anywhere. Your typing shows up here each time it closes."
                : "Type with the keyboard anywhere. Your typing shows up here each time it closes, once Allow Full Access is on."
        case (.iPhone, .said): "Tap the mic at the right end of the keyboard’s suggestions and talk."
        case (.mac, .typed): "Keystroke hasn’t counted any typing on your Mac yet."
        case (.mac, .said): "Keystroke hasn’t counted any dictation on your Mac yet."
        }
    }
}

private extension Activity.Kind {
    var verb: String { self == .typed ? "type" : "talk" }
    var noun: String { self == .typed ? "typed" : "said" }
}

private extension Date {
    var day: Date { Calendar.current.startOfDay(for: self) }

    func days(_ count: Int) -> Date { Calendar.current.date(byAdding: .day, value: count, to: day) ?? self }
}

/// How fast you type or talk, large, with a chip for how the last week compares, then how much and for how long.
private struct Speed: View {
    let kind: Activity.Kind
    let activity: Activity
    let device: StatsPage.Device

    private var all: Activity.Channel { activity.total(kind) }

    /// How many words a minute the last week is above or below all of it, once it's a whole one.
    private var trend: Int? {
        guard let speed = all.speed, let lately = activity.total(kind, since: Date.now.days(-6)).speed else { return nil }
        let change = Int((lately - speed).rounded())
        return change == 0 ? nil : change
    }

    private var fastest: (date: Date, speed: Double)? {
        activity.days.compactMap { date, day in
            let channel = kind == .typed ? day.typed : day.said
            return channel.seconds >= 120 ? channel.speed.map { (date, $0) } : nil
        }.max { $0.speed < $1.speed }
    }

    var body: some View {
        Card(footer: footer) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .typed ? "Typing speed" : "Talking speed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appSecondary)
                LeadNumber(value: all.speed.map { "\(Int($0.rounded())) wpm" } ?? "–", size: 52) {
                    if let trend { TrendChip(points: trend) }
                }
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.appDivider).frame(height: 1)
            Figures {
                Figure(value: all.words.formatted(), label: all.words == 1 ? "word \(kind.noun)" : "words \(kind.noun)")
                Figure(value: Self.time(all.seconds), label: kind == .typed ? "typing" : "talking")
                if kind == .said, all.dictations > 0 {
                    Figure(value: all.dictations.formatted(), label: all.dictations == 1 ? "dictation" : "dictations")
                } else {
                    let today = activity.channel(kind, on: Date.now.day).words
                    Figure(value: today.formatted(), label: "today")
                }
            }
        }
    }

    private var caption: String {
        var lines = [kind == .typed
            ? "Words of five letters a minute while you type, pauses over 4 seconds left out."
            : device == .mac ? "Words of five letters a minute, over the dictations Keystroke timed." : "Words a minute while you talk."]
        if kind == .said, let said = all.speed, let typed = activity.total(.typed).speed, typed > 0 {
            lines.append(String(format: "%.1f× as fast as you type.", said / typed))
        }
        if let fastest {
            lines.append("Fastest day: \(Int(fastest.speed.rounded()))\u{00A0}wpm, \(fastest.date.formatted(.dateTime.month(.abbreviated).day())).")
        }
        return lines.joined(separator: " ")
    }

    private var footer: String? {
        guard device == .mac else { return nil }
        let asOf = MacStats.shared.asOf.map { ", as of \($0.formatted(Calendar.current.isDateInToday($0) ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute()))" } ?? ""
        return "From Keystroke on your Mac\(asOf)."
    }

    static func time(_ seconds: Double) -> String {
        seconds < 60 ? "<1m" : Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }
}

/// Words typed or said each day for the last 30, today in the label color; a bar picked by a touch shows its day.
private struct WordsADay: View {
    let kind: Activity.Kind
    let activity: Activity
    @State private var picked: Date?

    private struct Day: Identifiable {
        let date: Date
        let words: Int
        var id: Date { date }
    }

    private var month: [Day] {
        (0 ..< 30).reversed().map { Date.now.days(-$0) }.map { Day(date: $0, words: activity.channel(kind, on: $0).words) }
    }

    var body: some View {
        let month = month
        let shown = picked.flatMap { date in month.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
        let active = month.filter { $0.words > 0 }
        Card(header: "Words a day") {
            VStack(alignment: .leading, spacing: 2) {
                SlotText(shown.map { $0.words.formatted() } ?? (active.isEmpty ? "0" : (active.reduce(0) { $0 + $1.words } / active.count).formatted()))
                    .font(.display(24))
                Text(shown.map { $0.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? "a day on the \(active.count) of the last 30 you \(kind.verb)")
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
            }
            .accessibilityElement(children: .combine)
            Chart(month) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words), width: .ratio(0.62))
                    .foregroundStyle(color(day, picked: shown))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous))
            }
            .chartXSelection(value: $picked)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.appDivider)
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
            .accessibilityLabel("Words a day, last 30 days")
        }
    }

    private func color(_ day: Day, picked: Day?) -> Color {
        if let picked { return day.date == picked.date ? .primary : Color.appSecondary.opacity(0.35) }
        return Calendar.current.isDateInToday(day.date) ? .primary : Color.appSecondary.opacity(0.55)
    }
}

/// The share of everything typed or said in each hour of the day, the busiest hour in the label color.
private struct Hours: View {
    let kind: Activity.Kind
    let channel: Activity.Channel

    private struct Hour: Identifiable {
        let hour: Int
        let share: Double
        var id: Int { hour }
        var label: String { String(hour) }
    }

    private var hours: [Hour] {
        let total = max(channel.hours.reduce(0, +), 1)
        return channel.hours.enumerated().map { Hour(hour: $0.offset, share: $0.element / total) }
    }

    private var busiest: Int? {
        channel.hours.reduce(0, +) > 0 ? channel.hours.indices.max { channel.hours[$0] < channel.hours[$1] } : nil
    }

    var body: some View {
        if let busiest {
            Card(header: "When you \(kind.verb)", footer: "Most between \(Self.name(busiest)) and \(Self.name((busiest + 1) % 24)).") {
                Chart(hours) { hour in
                    BarMark(x: .value("Hour", hour.label), y: .value("Share", hour.share), width: .ratio(0.7))
                        .foregroundStyle(hour.hour == busiest ? Color.primary : Color.appSecondary.opacity(0.55))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous))
                }
                .chartXAxis {
                    AxisMarks { value in
                        if let hour = value.as(String.self).flatMap(Int.init), hour % 6 == 0 {
                            AxisValueLabel(centered: false) { Text(Self.name(hour)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.appDivider)
                        AxisValueLabel {
                            if let share = value.as(Double.self) { Text(share, format: .percent.precision(.fractionLength(0))) }
                        }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("When you \(kind.verb), busiest at \(Self.name(busiest))")
            }
        }
    }

    static func name(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

/// Where the iPhone's typed words came from: as you typed them, fixed by autocorrect, or picked from the bar; then how
/// often you took a fix back, the keys you deleted and the emoji you added.
private struct WordSources: View {
    let channel: Activity.Channel

    var body: some View {
        let words = max(channel.words, 1)
        let corrected = min(channel.corrected, words), picked = min(channel.picked, words - corrected)
        let parts = [
            SegmentedBar.Part(name: "As typed", share: Double(words - corrected - picked) / Double(words), color: TapColor.aim),
            SegmentedBar.Part(name: "Autocorrected", share: Double(corrected) / Double(words), color: TapColor.miss),
            SegmentedBar.Part(name: "From the bar", share: Double(picked) / Double(words), color: Color.appSecondary.opacity(0.45)),
        ]
        Card(header: "Your typed words", footer: "Taken back: autocorrect’s fixes you undid with the bar. Deleted: the keys you tapped that were delete.") {
            SegmentedBar(parts: parts)
            Rectangle().fill(Color.appDivider).frame(height: 1)
            Figures {
                Figure(value: channel.corrected > 0 ? share(channel.undone, of: channel.corrected) : "–", label: "taken back")
                Figure(value: channel.keys > 0 ? share(channel.deletes, of: channel.keys) : "–", label: "deleted")
                Figure(value: channel.emoji.formatted(), label: "emoji")
            }
        }
    }

    private func share(_ part: Int, of whole: Int) -> String {
        (Double(part) / Double(whole)).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// One whole split into parts, each its own block with its share on it where it fits, and their names under it.
struct SegmentedBar: View {
    struct Part {
        let name: String
        let share: Double
        let color: Color
    }

    let parts: [Part]

    private var shown: [Part] { parts.filter { $0.share >= 0.005 } }

    private var legend: some View {
        ForEach(shown.indices, id: \.self) { index in
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(shown[index].color).frame(width: 8, height: 8)
                Text("\(shown[index].name) \(TapMapPalette.percent(shown[index].share))")
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let width = proxy.size.width - gap * CGFloat(shown.count - 1)
                HStack(spacing: gap) {
                    ForEach(shown.indices, id: \.self) { index in
                        let part = shown[index]
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(part.color)
                            .frame(width: max(width * part.share, 3))
                            .overlay(alignment: .leading) {
                                if width * part.share >= 48 {
                                    Text(TapMapPalette.percent(part.share))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.leading, 8)
                                }
                            }
                    }
                }
            }
            .frame(height: 28)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
            .font(.footnote)
            .foregroundStyle(Color.appSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown.map { "\($0.name) \(TapMapPalette.percent($0.share))" }.joined(separator: ", "))
    }
}

/// The apps your words went into, most first, each with a bar of its share; past the fifth, the rest as one.
private struct Apps: View {
    let kind: Activity.Kind
    let apps: [(name: String, words: Int)]

    private var rows: [(name: String, words: Int)] {
        guard apps.count > 6 else { return apps }
        return Array(apps.prefix(5)) + [("Other apps", apps.dropFirst(5).reduce(0) { $0 + $1.words })]
    }

    var body: some View {
        let top = Double(max(rows.map(\.words).max() ?? 1, 1))
        Card(header: kind == .typed ? "Where you type" : "Where you dictate") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows, id: \.name) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(app.name).lineLimit(1)
                            Spacer()
                            Text(app.words.formatted())
                                .monospacedDigit()
                                .foregroundStyle(Color.appSecondary)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(TapColor.aim.gradient)
                                .frame(width: max(proxy.size.width * Double(app.words) / top, 4))
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(app.name), \(app.words.formatted()) words")
                }
            }
        }
    }
}

/// The iPhone's dictations: how long they run, how many weren't typed, and the model that wrote most.
private struct Dictations: View {
    var body: some View {
        let all = Transcripts.shared.all.filter { !$0.text.isEmpty }
        let lengths = all.map(\.seconds).sorted()
        let models = Dictionary(grouping: all.compactMap(\.model), by: \.self).max { $0.value.count < $1.value.count }?.key
        if !lengths.isEmpty {
            Box(header: "Your dictations") {
                Fact(title: "Typical length", value: Self.length(lengths[lengths.count / 2]))
                Fact(title: "Longest", value: Self.length(lengths.last ?? 0))
                Fact(title: "Not typed", value: all.count(where: { !$0.typed }).formatted())
                if let models { Fact(title: "Written most by", value: models) }
            }
        }
    }

    private static func length(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
