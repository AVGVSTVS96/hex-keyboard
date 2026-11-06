import Charts
import KeyboardUI
import SwiftUI

/// Everything one device wrote, typed and said together, in typing's blue and dictation's pink: today, words or speed
/// a day over 7, 30 or 90 days, your records, the hours and speeds you write at, where your words went, the past year
/// and all of it. Wide, today, the history and the records take the first pane and the rest the second.
struct Overview: View {
    let activity: Activity
    let device: StatsPage.Device
    @Environment(\.arrangement) private var arrangement

    var body: some View {
        if arrangement == .side {
            Panes {
                Column(top: 4) { first }
            } second: {
                Column(top: 4) { second }
            }
        } else {
            Column(top: 4) {
                first
                second
            }
        }
    }

    @ViewBuilder private var first: some View {
        Today(activity: activity, device: device)
        History(activity: activity, kinds: [.typed, .said])
        Records(activity: activity)
    }

    @ViewBuilder private var second: some View {
        Rhythm(activity: activity, kinds: [.typed, .said])
        if !activity.speeds.isEmpty { Speeds(speeds: activity.speeds) }
        Talking(activity: activity)
        Year(activity: activity)
        AllTime(activity: activity)
    }
}

// MARK: The look

extension Activity.Kind {
    var color: Color { self == .typed ? .blue : .pink }
    var name: String { self == .typed ? "Typed" : "Dictated" }
}

/// A Stats card: a colored glyph, a title and a gray line on what it shows, at its top, then what it shows.
struct StatCard<Accessory: View, Content: View>: View {
    let symbol: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    heading
                    Spacer(minLength: 8)
                    accessory
                }
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    accessory
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: .rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(symbol: symbol, color: color, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension StatCard where Accessory == EmptyView {
    init(symbol: String, color: Color, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// Small pills for a card's own choices, the picked one filled.
struct ChoicePills<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                let picked = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(title(value))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(picked ? Color.appPillLabel : Color.appSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if picked { Capsule().fill(Color.appPill).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(Color.appPressed, in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A y-axis number in a set width, so a chart's plot keeps its place whether its top reads 500 or 40k.
struct AxisNumber: View {
    let value: AxisValue

    var body: some View {
        Text(value.as(Double.self).map { Format.short(Int($0)) } ?? "")
            .frame(width: 36, alignment: .leading)
    }
}

/// A dot and a name, for a chart's legend.
struct LegendDot: View {
    let color: Color
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).lineLimit(1)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.appSecondary)
    }
}

/// A small number over its label, in a card's grid of facts.
struct Stat: View {
    let label: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil
    var detailColor: Color = .appSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.appSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                SlotText(value)
                    .font(.display(22))
                    .tracking(-0.4)
                if let unit {
                    Text(unit)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.appSecondary)
                        .lineLimit(1)
                }
            }
            if let detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Facts all in one row where each gets room, else in rows of `columns`.
struct StatGrid<Content: View>: View {
    var columns = 2
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        Group(subviews: content) { facts in
            let across = width >= CGFloat(facts.count) * 118 ? facts.count : columns
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: across), alignment: .leading, spacing: 14) {
                ForEach(facts) { $0 }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

enum Format {
    /// 1,234 below ten thousand, 12.3k and 1.2M above.
    static func short(_ count: Int) -> String {
        count >= 10000 ? Double(count).formatted(.number.notation(.compactName).precision(.fractionLength(0 ... 1))).lowercased() : count.formatted()
    }

    /// The round number at or above `value` a chart's top reads: 1, 2, 2.5 or 5 times a power of ten.
    static func roundUp(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let power = pow(10, floor(log10(value)))
        return ([1, 2, 2.5, 5, 10].first { $0 * power >= value } ?? 10) * power
    }

    static func speed(_ speed: Double?) -> String { speed.map { "\(Int($0.rounded()))" } ?? "–" }

    static func time(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }

    static func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }

    static func hour(_ hour: Int) -> String {
        (Calendar.current.date(from: DateComponents(hour: hour)) ?? .now).formatted(.dateTime.hour())
    }

    /// How much `now` is above or below `before`, as +12% or −3%, once there's a before.
    static func change(_ now: Double, _ before: Double) -> (text: String, up: Bool)? {
        guard before > 0 else { return nil }
        let share = now / before - 1
        guard abs(share) >= 0.005 else { return nil }
        return ("\(share > 0 ? "↑" : "↓") \(abs(share).formatted(.percent.precision(.fractionLength(0)))) vs previous", share > 0)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: startOfDay) ?? self }
}

extension Activity {
    func both(on day: Date) -> Channel { channel(.typed, on: day) + channel(.said, on: day) }

    /// Days with words in them, oldest first.
    var activeDays: [Date] { days.filter { $0.value.typed.words + $0.value.said.words > 0 }.keys.sorted() }
}

// MARK: Today

/// Today's words, large, split typed and said, then today's typing speed, time, accuracy and keys.
private struct Today: View {
    let activity: Activity
    let device: StatsPage.Device

    var body: some View {
        let today = Date.now.startOfDay
        let typed = activity.channel(.typed, on: today), said = activity.channel(.said, on: today)
        let words = typed.words + said.words
        StatCard(symbol: "calendar", color: .orange, title: "Today", subtitle: today.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
            if case let .computer(name) = device, let asOf = Computers.shared.asOf[name] {
                Text(asOf.formatted(.relative(presentation: .named)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.appSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appPressed, in: .capsule)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SlotText(words.formatted())
                        .font(.display(52))
                        .tracking(-1.5)
                    Text(words == 1 ? "word" : "words")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.appSecondary)
                }
                .accessibilityElement(children: .combine)
                Split(parts: [(Activity.Kind.typed.color, Double(typed.words)), (Activity.Kind.said.color, Double(said.words))])
                HStack(spacing: 14) {
                    LegendDot(color: Activity.Kind.typed.color, name: "Typed \(typed.words.formatted())")
                    LegendDot(color: Activity.Kind.said.color, name: "Dictated \(said.words.formatted())")
                }
            }
            Rectangle().fill(Color.appDivider).frame(height: 1)
            StatGrid {
                let speed = typed.seconds >= 10 ? typed.paced / typed.seconds * 60 : nil
                Stat(label: "Typing speed", value: Format.speed(speed), unit: speed == nil ? nil : "wpm")
                Stat(label: "Active time", value: Format.time(typed.seconds + said.seconds))
                Stat(
                    label: "Accuracy", value: typed.keys > 0 ? (1 - Double(typed.deletes) / Double(typed.keys)).formatted(.percent.precision(.fractionLength(0))) : "–",
                    detail: typed.keys > 0 ? "\(typed.deletes.formatted()) deleted" : nil
                )
                Stat(label: "Keystrokes", value: typed.keys.formatted())
            }
        }
    }
}

/// A whole split into colored parts with a hairline between them, empty while there's nothing.
struct Split: View {
    let parts: [(color: Color, value: Double)]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let total = parts.reduce(0) { $0 + $1.value }
            let shown = parts.filter { $0.value > 0 }
            let gap: CGFloat = shown.count > 1 ? 2 : 0
            let width = proxy.size.width - gap * CGFloat(max(shown.count - 1, 0))
            HStack(spacing: gap) {
                if total > 0 {
                    ForEach(shown.indices, id: \.self) { index in
                        Capsule().fill(shown[index].color.gradient).frame(width: max(width * shown[index].value / total, height))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appPressed, in: .capsule)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: History

/// Words a day, typed and said stacked, or each one's speed a day, over 7, 30 or 90 days, under how the span did
/// against the one before; a day touched shows its own.
struct History: View {
    let activity: Activity
    let kinds: [Activity.Kind]
    @State private var measure = Measure.words
    @State private var span = 30
    @State private var picked: Date?

    enum Measure: String, CaseIterable { case words = "Words", speed = "Speed" }

    private struct Point: Identifiable {
        let date: Date
        let kind: Activity.Kind
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)\(kind)" }
    }

    private func range(_ days: Int, back: Int = 0) -> [Date] {
        (0 ..< days).reversed().map { Date.now.adding(days: -$0 - back) }
    }

    private func total(_ dates: [Date]) -> Activity.Channel {
        dates.reduce(Activity.Channel()) { sum, date in kinds.reduce(sum) { $0 + activity.channel($1, on: date) } }
    }

    private func speed(_ channel: Activity.Channel) -> Double? { channel.seconds >= 60 ? channel.paced / channel.seconds * 60 : nil }

    var body: some View {
        let dates = range(span)
        let points = dates.flatMap { date in
            kinds.compactMap { kind -> Point? in
                let channel = activity.channel(kind, on: date)
                switch measure {
                case .words: return Point(date: date, kind: kind, value: Double(channel.words))
                case .speed: return channel.seconds >= 30 ? Point(date: date, kind: kind, value: channel.paced / channel.seconds * 60) : nil
                }
            }
        }
        let shown = picked.flatMap { date in dates.first { Calendar.current.isDate($0, inSameDayAs: date) } }
        let top = Format.roundUp(measure == .words
            ? dates.map { date in kinds.reduce(0) { $0 + Double(activity.channel($1, on: date).words) } }.max() ?? 0
            : points.map(\.value).max() ?? 0)
        StatCard(symbol: "chart.bar.fill", color: .indigo, title: "History", subtitle: measure == .words ? "Words written per day" : "Words a minute per day") {
            HStack(spacing: 6) {
                ChoicePills(values: Measure.allCases, selection: $measure) { $0.rawValue }
                ChoicePills(values: [7, 30, 90], selection: $span) { "\($0)D" }
            }
        } content: {
            Group {
                if let shown { day(shown) } else { summary(dates) }
            }
            .frame(minHeight: 58, alignment: .topLeading)
            Chart(points) { point in
                switch measure {
                case .words:
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Words", point.value), width: .ratio(span > 30 ? 0.8 : 0.66))
                        .foregroundStyle(by: .value("Kind", point.kind.name))
                        .opacity(shown == nil || shown == point.date ? 1 : 0.35)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: span > 30 ? 1.5 : 3, topTrailingRadius: span > 30 ? 1.5 : 3, style: .continuous))
                case .speed:
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("WPM", point.value))
                        .foregroundStyle(by: .value("Kind", point.kind.name))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("WPM", point.value))
                        .foregroundStyle(by: .value("Kind", point.kind.name))
                        .symbolSize(span > 30 ? 10 : 22)
                }
                if let shown, shown == point.date, point.kind == kinds.first {
                    RuleMark(x: .value("Day", shown, unit: .day))
                        .foregroundStyle(Color.appSecondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartForegroundStyleScale(domain: kinds.map(\.name), range: kinds.map { $0.color.gradient })
            .chartYScale(domain: 0 ... top)
            .chartLegend(.hidden)
            .chartXSelection(value: $picked)
            .chartXScale(domain: dates[0] ... Date.now.adding(days: 1))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: span == 7 ? 1 : span == 30 ? 7 : 30)) { _ in
                    AxisValueLabel(format: span == 7 ? .dateTime.weekday(.narrow) : .dateTime.month(.abbreviated).day(), centered: span == 7)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, top / 2, top]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(Color.appDivider)
                    AxisValueLabel { AxisNumber(value: value) }
                }
            }
            .frame(height: 170)
            .animation(.snappy, value: span)
            .animation(.snappy, value: measure)
            .accessibilityLabel("\(measure.rawValue) a day, last \(span) days")
            if kinds.count > 1 {
                HStack(spacing: 14) { ForEach(kinds, id: \.self) { LegendDot(color: $0.color, name: $0.name) } }
            }
        }
    }

    @ViewBuilder private func summary(_ dates: [Date]) -> some View {
        let now = total(dates), before = total(range(span, back: span))
        let active = dates.count { date in kinds.contains { activity.channel($0, on: date).words > 0 } }
        let words = change(Double(now.words), Double(before.words))
        let pace = speed(now).flatMap { now in speed(before).flatMap { change(now, $0) } }
        StatGrid {
            Stat(label: "Words · \(span)d", value: Format.short(now.words), detail: words?.text, detailColor: words.map { $0.up ? .green : .orange } ?? .appSecondary)
            Stat(label: "Per active day", value: Format.short(active > 0 ? now.words / active : 0))
            Stat(label: "Speed", value: Format.speed(speed(now)), unit: "wpm", detail: pace?.text, detailColor: pace.map { $0.up ? .green : .orange } ?? .appSecondary)
            Stat(label: "Active days", value: "\(active)", unit: "of \(span)")
        }
    }

    private func change(_ now: Double, _ before: Double) -> (text: String, up: Bool)? { Format.change(now, before) }

    @ViewBuilder private func day(_ date: Date) -> some View {
        StatGrid(columns: 3) {
            Stat(label: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), value: Format.short(kinds.reduce(0) { $0 + activity.channel($1, on: date).words }), unit: "words")
            ForEach(kinds, id: \.self) { kind in
                let channel = activity.channel(kind, on: date)
                Stat(label: kind.name, value: Format.short(channel.words), detail: speed(channel).map { "\(Int($0.rounded())) wpm" }, detailColor: kind.color)
            }
        }
    }
}

// MARK: Records

/// Your streak, the day you wrote most, your fastest day and your fastest stretch, each a tile.
private struct Records: View {
    let activity: Activity

    var body: some View {
        let streak = streaks
        let most = activity.days.max { $0.value.typed.words + $0.value.said.words < $1.value.typed.words + $1.value.said.words }
        let fastest = activity.days.compactMap { date, day in day.typed.seconds >= 120 ? day.typed.speed.map { (date, $0) } : nil }.max { $0.1 < $1.1 }
        let burst = activity.days.map { ($0.key, $0.value.typed.peak) }.max { $0.1 < $1.1 }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            Record(symbol: "flame.fill", color: .orange, title: "Streak", value: "\(streak.current)", unit: streak.current == 1 ? "day" : "days", detail: "Longest \(streak.longest) days")
            Record(
                symbol: "trophy.fill", color: .yellow, title: "Most words", value: Format.short(most.map { $0.value.typed.words + $0.value.said.words } ?? 0), unit: "words",
                detail: most.map { Format.day($0.key) } ?? "–"
            )
            Record(symbol: "gauge.with.dots.needle.67percent", color: .green, title: "Fastest day", value: Format.speed(fastest?.1), unit: "wpm", detail: fastest.map { Format.day($0.0) } ?? "Two minutes of typing a day")
            Record(
                symbol: "bolt.fill", color: .purple, title: "Top burst", value: Format.speed((burst?.1 ?? 0) > 0 ? burst?.1 : nil), unit: "wpm",
                detail: burst.flatMap { $0.1 > 0 ? Format.day($0.0) : nil } ?? "–"
            )
        }
    }

    /// Days in a row with words, up to today (or yesterday, while today has none yet), and the most ever.
    private var streaks: (current: Int, longest: Int) {
        let days = Set(activity.activeDays)
        var longest = 0, run = 0, previous: Date?
        for day in days.sorted() {
            run = previous.map { Calendar.current.dateComponents([.day], from: $0, to: day).day == 1 } == true ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        var current = 0, day = Date.now.startOfDay
        if !days.contains(day) { day = day.adding(days: -1) }
        while days.contains(day) {
            current += 1
            day = day.adding(days: -1)
        }
        return (current, longest)
    }
}

private struct Record: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let unit: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.18), in: .circle)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    SlotText(value)
                        .font(.display(30))
                        .tracking(-0.8)
                    Text(unit)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.appSecondary)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.appSecondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous)
                .fill(Color.appCard)
                .overlay(alignment: .topLeading) {
                    Circle().fill(color.opacity(0.16)).frame(width: 120, height: 120).blur(radius: 40).offset(x: -40, y: -50)
                }
                .clipShape(.rect(cornerRadius: AppStyle.cardRadius, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius, style: .continuous).strokeBorder(Color.appEdge))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Rhythm

/// The hours of the day you write in, typed and said stacked, in words.
struct Rhythm: View {
    let activity: Activity
    let kinds: [Activity.Kind]

    private struct Hour: Identifiable {
        let hour: Int
        let kind: Activity.Kind
        let words: Double
        var id: String { "\(hour)\(kind)" }
    }

    var body: some View {
        let hours = kinds.flatMap { kind in activity.total(kind).hours.enumerated().map { Hour(hour: $0.offset, kind: kind, words: $0.element / 5) } }
        let sums = (0 ..< 24).map { hour in hours.filter { $0.hour == hour }.reduce(0) { $0 + $1.words } }
        if let busiest = sums.indices.max(by: { sums[$0] < sums[$1] }), sums[busiest] > 0 {
            let top = Format.roundUp(sums[busiest])
            StatCard(symbol: "clock.fill", color: .teal, title: "Daily rhythm", subtitle: "Most active around \(Format.hour(busiest))") {
                Chart(hours) { hour in
                    BarMark(x: .value("Hour", "\(hour.hour)"), y: .value("Words", hour.words), width: .ratio(0.72))
                        .foregroundStyle(by: .value("Kind", hour.kind.name))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous))
                }
                .chartForegroundStyleScale(domain: kinds.map(\.name), range: kinds.map { $0.color.gradient })
                .chartLegend(.hidden)
                .chartXScale(domain: (0 ..< 24).map { "\($0)" })
                .chartYScale(domain: 0 ... top)
                .chartXAxis {
                    AxisMarks { value in
                        if let hour = value.as(String.self).flatMap(Int.init), hour % 6 == 0 {
                            AxisValueLabel(anchor: .topLeading) { Text(Format.hour(hour)) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, top / 2, top]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(Color.appDivider)
                        AxisValueLabel { AxisNumber(value: value) }
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Words by hour of day, busiest around \(Format.hour(busiest))")
                if kinds.count > 1 {
                    HStack(spacing: 14) { ForEach(kinds, id: \.self) { LegendDot(color: $0.color, name: $0.name) } }
                }
            }
        }
    }
}

// MARK: Speeds

/// How often you type at each speed, a column per 5 wpm, warmer the faster, the usual span and the median above.
struct Speeds: View {
    let speeds: [Int: Double]

    private var bands: [(speed: Int, count: Double)] { speeds.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }

    /// The speed at which `share` of all stretches are slower.
    private func percentile(_ share: Double) -> Int {
        let total = bands.reduce(0) { $0 + $1.count }
        var seen = 0.0
        for band in bands {
            seen += band.count
            if seen >= total * share { return band.speed + 2 }
        }
        return bands.last?.speed ?? 0
    }

    var body: some View {
        let low = percentile(0.1) / 5 * 5, high = (percentile(0.9) + 4) / 5 * 5, median = percentile(0.5)
        StatCard(symbol: "speedometer", color: .blue, title: "Typing speed", subtitle: "Usually \(low)–\(high) wpm · median ~\(median) wpm") {
            Chart(bands, id: \.speed) { band in
                BarMark(x: .value("WPM", "\(band.speed)"), y: .value("Stretches", band.count), width: .ratio(0.78))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.cyan, .blue, .indigo].map { $0.opacity(band.speed >= low && band.speed <= high ? 1 : 0.45) }, startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2, style: .continuous))
            }
            .chartXScale(domain: bands.map { "\($0.speed)" })
            .chartXAxis {
                AxisMarks { value in
                    if let speed = value.as(String.self), (Int(speed) ?? 1) % 20 == 0 {
                        AxisValueLabel(anchor: .topLeading) { Text(speed) }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 130)
            .accessibilityLabel("Typing speed: usually \(low) to \(high) words a minute, median about \(median)")
            Text("Words a minute, each column a stretch of typing")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
        }
    }
}

// MARK: Talking

/// Every word you've dictated, its share of all you've written, how fast you talk, and the apps your words went into,
/// typed and said side by side.
private struct Talking: View {
    let activity: Activity

    private struct App: Identifiable {
        let name: String
        var typed = 0
        var said = 0
        var id: String { name }
        var words: Int { typed + said }
    }

    private var apps: [App] {
        var apps: [String: App] = [:]
        for (name, words) in activity.apps[.typed] ?? [] { apps[name, default: App(name: name)].typed += words }
        for (name, words) in activity.apps[.said] ?? [] { apps[name, default: App(name: name)].said += words }
        return apps.values.sorted { $0.words > $1.words }.prefix(5).map { $0 }
    }

    var body: some View {
        let said = activity.total(.said), typed = activity.total(.typed)
        let all = said.words + typed.words
        if all > 0 {
            StatCard(symbol: "waveform", color: .pink, title: "Dictation", subtitle: "Voice to text, in every total") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SlotText(said.words.formatted())
                            .font(.display(40))
                            .tracking(-1)
                        Text("words dictated")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.appSecondary)
                    }
                    Split(parts: [(Activity.Kind.said.color, Double(said.words)), (Activity.Kind.typed.color.opacity(0.35), Double(typed.words))])
                    Text("\((Double(said.words) / Double(all)).formatted(.percent.precision(.fractionLength(0)))) of everything you’ve written")
                        .font(.footnote)
                        .foregroundStyle(Color.appSecondary)
                }
                StatGrid(columns: 3) {
                    Stat(label: "Speaking", value: Format.speed(said.speed), unit: "wpm", detail: said.speed.flatMap { s in typed.speed.map { String(format: "%.1f× your typing", s / $0) } }, detailColor: .pink)
                    Stat(label: "Dictations", value: said.dictations.formatted())
                    Stat(label: "Avg length", value: said.dictations > 0 ? "\(said.words / said.dictations)" : "–", unit: "words")
                }
                let apps = apps
                if !apps.isEmpty {
                    Rectangle().fill(Color.appDivider).frame(height: 1)
                    Text("By app")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appSecondary)
                    let top = Double(apps.first?.words ?? 1)
                    VStack(spacing: 14) {
                        ForEach(apps) { app in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(app.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    Text("\(Format.short(app.words)) words")
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.appSecondary)
                                }
                                GeometryReader { proxy in
                                    Split(parts: [(Activity.Kind.typed.color, Double(app.typed)), (Activity.Kind.said.color, Double(app.said))], height: 6)
                                        .frame(width: max(proxy.size.width * Double(app.words) / top, 6))
                                }
                                .frame(height: 6)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(app.name), \(app.typed.formatted()) typed, \(app.said.formatted()) dictated")
                        }
                    }
                    if apps.contains(where: { $0.typed > 0 }) {
                        HStack(spacing: 14) { ForEach([Activity.Kind.typed, .said], id: \.self) { LegendDot(color: $0.color, name: $0.name) } }
                    }
                }
            }
        }
    }
}

// MARK: Year

/// A square a day for as many weeks back as fit, up to a year, brighter the more you wrote, bluer for typing and
/// pinker for dictation.
struct Year: View {
    let activity: Activity
    var kinds: [Activity.Kind] = [.typed, .said]

    private let cell: CGFloat = 10, gap: CGFloat = 3, left: CGFloat = 26
    @State private var width: CGFloat = 0

    private var weeks: Int { max(1, min(53, Int((width - left + gap) / (cell + gap)))) }

    var body: some View {
        let since = Date.now.adding(days: -weeks * 7)
        let active = activity.days.count { date, _ in date > since && words(date).typed + words(date).said > 0 }
        let months = Int((Double(weeks) / 4.35).rounded())
        StatCard(symbol: "square.grid.3x3.fill", color: .green, title: weeks >= 52 ? "Past year" : "Past \(months) months", subtitle: "\(active) active \(active == 1 ? "day" : "days") · shaded by words written") {
            Canvas { context, size in draw(in: &context, size: size) }
                .accessibilityHidden(true)
                .frame(height: 7 * cell + 6 * gap + 18)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            HStack(spacing: 4) {
                if kinds.count > 1 {
                    LegendDot(color: Activity.Kind.typed.color, name: "Typed")
                    LegendDot(color: Activity.Kind.said.color, name: "Dictated")
                }
                Spacer()
                Text("Less").font(.caption).foregroundStyle(Color.appSecondary)
                ForEach(0 ..< 5) { level in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(level == 0 ? AnyShapeStyle(Color.appPressed) : AnyShapeStyle(LinearGradient(colors: kinds.map { $0.color.opacity([0, 0.3, 0.5, 0.75, 1][level]) }, startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption).foregroundStyle(Color.appSecondary)
            }
        }
    }

    private func words(_ date: Date) -> (typed: Int, said: Int) {
        (kinds.contains(.typed) ? activity.channel(.typed, on: date).words : 0, kinds.contains(.said) ? activity.channel(.said, on: date).words : 0)
    }

    private func shade(level: Int, said: Double) -> Color {
        guard level > 0 else { return Color.appPressed }
        let typed = UIColor(Activity.Kind.typed.color), pink = UIColor(Activity.Kind.said.color)
        let color = kinds == [.said] ? pink : kinds == [.typed] ? typed : Self.mix(typed, pink, said)
        return Color(color).opacity([0, 0.3, 0.5, 0.75, 1][level])
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ t: Double) -> UIColor {
        var (r1, g1, b1, a1, r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let top: CGFloat = 16
        let calendar = Calendar.current
        let today = Date.now.startOfDay
        let weekday = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let start = today.adding(days: -(weeks - 1) * 7 - weekday)
        let totals = (0 ..< weeks * 7).map { words(start.adding(days: $0)) }.map { $0.typed + $0.said }.filter { $0 > 0 }.sorted()
        func level(_ value: Int) -> Int {
            guard value > 0, !totals.isEmpty else { return 0 }
            let rank = Double(totals.firstIndex { $0 >= value } ?? totals.count - 1) / Double(max(totals.count - 1, 1))
            return min(4, 1 + Int(rank * 4))
        }
        let label = Color.appSecondary
        for row in [1, 3, 5] {
            let name = calendar.shortWeekdaySymbols[(row + calendar.firstWeekday - 1) % 7]
            context.draw(Text(name).font(.system(size: 9, weight: .medium)).foregroundStyle(label), at: CGPoint(x: 0, y: top + CGFloat(row) * (cell + gap) + cell / 2), anchor: .leading)
        }
        var lastMonth = -1
        for week in 0 ..< weeks {
            let x = left + CGFloat(week) * (cell + gap)
            let first = start.adding(days: week * 7)
            let month = calendar.component(.month, from: first)
            if month != lastMonth, week < weeks - 2 {
                if lastMonth != -1 || calendar.component(.day, from: first) <= 7 {
                    context.draw(Text(first.formatted(.dateTime.month(.abbreviated))).font(.system(size: 9, weight: .medium)).foregroundStyle(label), at: CGPoint(x: x, y: 5), anchor: .leading)
                }
                lastMonth = month
            }
            for day in 0 ..< 7 {
                let date = start.adding(days: week * 7 + day)
                guard date <= today else { continue }
                let value = words(date)
                let total = value.typed + value.said
                let rect = CGRect(x: x, y: top + CGFloat(day) * (cell + gap), width: cell, height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(shade(level: level(total), said: total > 0 ? Double(value.said) / Double(total) : 0)))
                if date == today {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 3.5), with: .color(.primary.opacity(0.7)), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: All time

/// Everything since the first day counted.
private struct AllTime: View {
    let activity: Activity

    var body: some View {
        let typed = activity.total(.typed), said = activity.total(.said)
        if let first = activity.activeDays.first {
            StatCard(symbol: "infinity", color: .gray, title: "All time", subtitle: "Since \(first.formatted(.dateTime.month(.abbreviated).day().year()))") {
                StatGrid(columns: 3) {
                    Stat(label: "Words", value: Format.short(typed.words + said.words))
                    Stat(label: "Typed", value: Format.short(typed.words), detail: typed.speed.map { "\(Int($0.rounded())) wpm" }, detailColor: Activity.Kind.typed.color)
                    Stat(label: "Dictated", value: Format.short(said.words), detail: said.speed.map { "\(Int($0.rounded())) wpm" }, detailColor: Activity.Kind.said.color)
                    Stat(label: "Active time", value: Format.time(typed.seconds + said.seconds))
                    Stat(label: "Keystrokes", value: Format.short(typed.keys))
                    Stat(label: "Active days", value: "\(activity.activeDays.count)")
                }
            }
        }
    }
}
