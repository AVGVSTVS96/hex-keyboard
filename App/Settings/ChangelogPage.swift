import Foundation
import SwiftUI

/// What changed in each build, a box per day, newest first. scripts/phone writes the list into the app's Info.plist as
/// `IIKBChangelog`, from each commit's `Changelog:` trailer and App/Settings/changelog.tsv.
struct ChangelogPage: View {
    private struct Change: Hashable {
        let build: Int
        let text: String
    }

    private struct Day {
        let date: Date
        var changes: [Change]

        var title: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private static func days() -> [Day] {
        let rows = Bundle.main.object(forInfoDictionaryKey: "IIKBChangelog") as? [[String: Any]] ?? []
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var days: [Day] = []
        for row in rows {
            guard let build = row["build"] as? Int, let text = row["change"] as? String,
                  let date = row["date"] as? String, let parsed = parser.date(from: date) else { continue }
            let day = calendar.startOfDay(for: parsed)
            let change = Change(build: build, text: text)
            if let index = days.firstIndex(where: { $0.date == day }) {
                days[index].changes.append(change)
            } else {
                days.append(Day(date: day, changes: [change]))
            }
        }
        return days.sorted { $0.date > $1.date }
    }

    var body: some View {
        let days = Self.days()
        VStack(alignment: .leading, spacing: 28) {
            if days.isEmpty {
                Box {
                    RowText(title: "No changes listed in this build.").row()
                }
            }
            ForEach(days, id: \.date) { day in
                Box(header: day.title) {
                    ForEach(day.changes, id: \.self) { change in
                        HStack(spacing: 14) {
                            RowText(title: change.text)
                            Text(String(change.build))
                                .foregroundStyle(Color.appSecondary)
                                .monospacedDigit()
                        }
                        .row()
                    }
                }
            }
        }
    }
}
