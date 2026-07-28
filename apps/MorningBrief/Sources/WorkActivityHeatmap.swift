import SwiftUI

/// GitHub-style contribution grid that fills the offered bounds.
///
/// Cell size and week count are derived from the container so the calendar
/// reads as a dense plane instead of a small left-aligned stamp.
struct WorkActivityHeatmap: View {
    let selectedDate: String
    let counts: [String: Int]
    /// Soft preference; actual weeks shrink/grow to fill width.
    var preferredWeeks: Int = 16
    let onSelectDay: (String) -> Void

    private let today = BriefPaths.todayDateString()
    private let minCell: CGFloat = 7
    private let maxCell: CGFloat = 16
    private let gap: CGFloat = 2
    private let labelWidth: CGFloat = 10

    private var maxCount: Int {
        counts.values.max() ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = layoutMetrics(in: geo.size)
            let columns = weekColumns(weeks: metrics.weeks)
            HStack(alignment: .center, spacing: 3) {
                weekdayLabels(cell: metrics.cell)
                HStack(spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                cellView(column[safe: row] ?? nil, cell: metrics.cell)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作跨度日历")
    }

    private struct Metrics {
        let cell: CGFloat
        let weeks: Int
    }

    private func layoutMetrics(in size: CGSize) -> Metrics {
        let safeWidth = max(0, size.width - labelWidth - 3)
        let safeHeight = max(0, size.height)
        // Fill height with 7 rows, then pick as many weeks as width allows.
        let cellFromHeight = safeHeight > 0
            ? (safeHeight - gap * 6) / 7
            : minCell
        let cell = min(maxCell, max(minCell, cellFromHeight))
        let weeksFromWidth = Int(floor((safeWidth + gap) / (cell + gap)))
        let weeks = max(6, min(26, weeksFromWidth > 0 ? weeksFromWidth : preferredWeeks))
        return Metrics(cell: cell, weeks: weeks)
    }

    /// Week columns; each column is Mon…Sun (`nil` = padding / future).
    private func weekColumns(weeks: Int) -> [[String?]] {
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
        if result.count > weeks {
            result = Array(result.suffix(weeks))
        }
        return result
    }

    private func weekdayLabels(cell: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { index, label in
                Text(index % 2 == 0 ? label : "")
                    .font(.system(size: max(7, cell * 0.75)))
                    .foregroundStyle(.tertiary)
                    .frame(width: labelWidth, height: cell, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: String?, cell: CGFloat) -> some View {
        if let day {
            let count = counts[day, default: 0]
            let selected = day == selectedDate
            Button {
                onSelectDay(day)
            } label: {
                RoundedRectangle(cornerRadius: max(1.5, cell * 0.22), style: .continuous)
                    .fill(fillColor(for: count))
                    .frame(width: cell, height: cell)
                    .overlay {
                        RoundedRectangle(cornerRadius: max(1.5, cell * 0.22), style: .continuous)
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
        return Color(red: 0.22, green: 0.62, blue: 0.36).opacity(level)
    }

    private func mondayOnOrBefore(_ day: String) -> String? {
        guard let start = BriefPaths.startOfDay(forDateString: day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BriefPaths.dayTimeZone
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
