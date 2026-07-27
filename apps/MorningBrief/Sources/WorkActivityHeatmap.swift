import SwiftUI

/// GitHub-style contribution grid: columns = weeks, rows = Mon→Sun, fill depth = span count.
struct WorkActivityHeatmap: View {
    let selectedDate: String
    let counts: [String: Int]
    var weeks: Int = 13
    let onSelectDay: (String) -> Void

    private let cell: CGFloat = 11
    private let gap: CGFloat = 2
    private let today = BriefPaths.todayDateString()

    private var maxCount: Int {
        counts.values.max() ?? 0
    }

    /// Week columns; each column is Mon…Sun (`nil` = padding outside the data window).
    private var columns: [[String?]] {
        guard weeks > 0,
              let rawStart = BriefPaths.dayString(byAddingDays: -(weeks * 7 - 1), to: today),
              let alignedStart = mondayOnOrBefore(rawStart),
              let sundayEnd = sundayOnOrAfter(today)
        else { return [] }

        let days = BriefPaths.dayStrings(from: alignedStart, through: sundayEnd)
        guard !days.isEmpty else { return [] }
        var result: [[String?]] = []
        var index = 0
        while index < days.count {
            var column: [String?] = []
            for row in 0..<7 {
                let day = index + row < days.count ? days[index + row] : nil
                if let day, day > today {
                    column.append(nil)
                } else {
                    column.append(day)
                }
            }
            result.append(column)
            index += 7
        }
        // Keep the most recent `weeks` columns if padding expanded the range.
        if result.count > weeks {
            result = Array(result.suffix(weeks))
        }
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            weekdayLabels
            HStack(spacing: gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            cellView(column[row])
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作跨度日历")
    }

    private var weekdayLabels: some View {
        VStack(spacing: gap) {
            ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { index, label in
                Text(index % 2 == 0 ? label : "")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, height: cell, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: String?) -> some View {
        if let day {
            let count = counts[day, default: 0]
            let selected = day == selectedDate
            Button {
                onSelectDay(day)
            } label: {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fillColor(for: count))
                    .frame(width: cell, height: cell)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                selected ? Color.primary.opacity(0.85) : Color.clear,
                                lineWidth: selected ? 1.5 : 0
                            )
                    }
            }
            .buttonStyle(.plain)
            .help("\(day)：\(count) 个任务跨度")
            .accessibilityLabel("\(day)，\(count) 个任务")
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func fillColor(for count: Int) -> Color {
        if count <= 0 {
            return Color.primary.opacity(0.06)
        }
        let maxValue = max(maxCount, 1)
        let ratio = Double(count) / Double(maxValue)
        let level: Double
        if ratio <= 0.25 {
            level = 0.28
        } else if ratio <= 0.5 {
            level = 0.48
        } else if ratio <= 0.75 {
            level = 0.68
        } else {
            level = 0.9
        }
        // Green contribution scale (readable in light/dark via opacity on a solid green).
        return Color(red: 0.22, green: 0.62, blue: 0.36).opacity(level)
    }

    private func mondayOnOrBefore(_ day: String) -> String? {
        guard let start = BriefPaths.startOfDay(forDateString: day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BriefPaths.dayTimeZone
        // weekday: 1 = Sunday … 7 = Saturday. Convert to days since Monday.
        let weekday = calendar.component(.weekday, from: start)
        let daysFromMonday = (weekday + 5) % 7
        return BriefPaths.dayString(byAddingDays: -daysFromMonday, to: day)
    }

    private func sundayOnOrAfter(_ day: String) -> String? {
        guard let start = BriefPaths.startOfDay(forDateString: day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BriefPaths.dayTimeZone
        let weekday = calendar.component(.weekday, from: start)
        let daysToSunday = (8 - weekday) % 7
        return BriefPaths.dayString(byAddingDays: daysToSunday, to: day)
    }
}
