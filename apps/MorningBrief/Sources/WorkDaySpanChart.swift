import SwiftUI

/// Single work-ledger surface: date×task span chart with status chrome and hover detail.
struct WorkDaySpanChart: View {
    let spans: [WorkDaySpan]
    let onSelect: (WorkItem) -> Void

    @State private var hoveredID: String?
    @State private var statusFilter: Set<WorkStatus> = []

    private let dayRowHeight: CGFloat = 28
    private let dateGutter: CGFloat = 44
    private let laneWidth: CGFloat = 76
    private let headerHeight: CGFloat = 52

    private var chartDays: [String] {
        spans.first?.chartDays ?? []
    }

    private var visibleSpans: [WorkDaySpan] {
        guard !statusFilter.isEmpty else { return spans }
        return spans.filter { statusFilter.contains($0.item.status) }
    }

    private var hoveredSpan: WorkDaySpan? {
        guard let hoveredID else { return nil }
        return spans.first { $0.id == hoveredID }
    }

    private var statusOrder: [WorkStatus] {
        WorkStatus.chartFilterStatuses
    }

    private var counts: [WorkStatus: Int] {
        var result: [WorkStatus: Int] = [:]
        for span in spans {
            result[span.item.status, default: 0] += 1
        }
        return result
    }

    private var timelineHeight: CGFloat {
        max(dayRowHeight, CGFloat(chartDays.count) * dayRowHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            statusLegend
            if spans.isEmpty {
                emptyState
            } else {
                hoverCard
                chartScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.22), value: hoveredID)
    }

    private var emptyState: some View {
        Text("暂无任务跨度")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, DS.Space.md)
    }

    private var statusLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DS.Space.xs) {
                Text("任务跨度")
                    .font(.caption.weight(.semibold))
                Text("\(spans.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if !statusFilter.isEmpty {
                    Button("显示全部") {
                        statusFilter = []
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(statusOrder, id: \.self) { status in
                        let count = counts[status, default: 0]
                        statusChip(status, count: count)
                    }
                }
            }
        }
    }

    private func statusChip(_ status: WorkStatus, count: Int) -> some View {
        let active = statusFilter.isEmpty || statusFilter.contains(status)
        let selected = statusFilter.contains(status)
        return Button {
            toggleFilter(status)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: status.iconName)
                    .font(.system(size: 9, weight: .semibold))
                Text(status.title)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(active ? status.chartTint : Color.secondary.opacity(0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(status.chartTint.opacity(selected ? 0.22 : (active ? 0.1 : 0.04)))
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        status.chartTint.opacity(selected ? 0.7 : 0),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.35 : 1)
        .accessibilityLabel("\(status.title) \(count)")
        .accessibilityHint(selected ? "取消筛选" : "只显示该状态")
    }

    private func toggleFilter(_ status: WorkStatus) {
        if statusFilter.contains(status) {
            statusFilter.remove(status)
        } else {
            statusFilter.insert(status)
        }
    }

    private var hoverCard: some View {
        ZStack(alignment: .topLeading) {
            // Stable slot so hover in/out doesn't jump the chart.
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .frame(maxWidth: .infinity)
                .frame(height: 78)

            if let span = hoveredSpan {
                let item = span.item
                Button {
                    onSelect(item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: item.status.iconName)
                                .foregroundStyle(item.status.chartTint)
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(item.status.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(item.status.chartTint)
                        }
                        HStack(spacing: 8) {
                            Text(dateRangeLabel(span))
                            Text("·")
                            Text("\(span.spanDayCount) 天")
                            if let duration = item.wallClockDurationLabel {
                                Text("·")
                                Text(duration.replacingOccurrences(of: "已持续 ", with: ""))
                            }
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        if let progress = item.lastProgress, !progress.isEmpty {
                            Text(progress)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(item.status.chartTint.opacity(0.1))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .strokeBorder(item.status.chartTint.opacity(0.28), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 78)
                .transition(.opacity)
            }
        }
        .frame(height: 78)
    }

    private var chartScroll: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                dateScale
                    .frame(width: dateGutter)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(visibleSpans) { span in
                        laneColumn(span)
                            .frame(width: laneWidth)
                    }
                }
                .padding(.trailing, DS.Space.sm)
            }
            .padding(.bottom, DS.Space.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var dateScale: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerHeight)
            VStack(spacing: 0) {
                ForEach(Array(chartDays.enumerated()), id: \.offset) { _, day in
                    Text(dayTickLabel(day))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(day == BriefPaths.todayDateString() ? Color.primary : Color.secondary)
                        .fontWeight(day == BriefPaths.todayDateString() ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: dayRowHeight)
                        .padding(.trailing, 4)
                }
            }
        }
    }

    private func dayTickLabel(_ day: String) -> String {
        if day == BriefPaths.todayDateString() { return "今天" }
        if day.count >= 10 { return String(day.dropFirst(5)) }
        return day
    }

    private func laneColumn(_ span: WorkDaySpan) -> some View {
        let status = span.item.status
        let tint = Self.laneTint(for: span.item.id, status: status)
        let dimmed = hoveredID != nil && hoveredID != span.id
        return Button {
            onSelect(span.item)
        } label: {
            VStack(spacing: 4) {
                laneHeader(span)
                    .frame(height: headerHeight - 4, alignment: .bottom)

                ZStack(alignment: .top) {
                    // Day grid
                    VStack(spacing: 0) {
                        ForEach(Array(chartDays.enumerated()), id: \.offset) { _, day in
                            Rectangle()
                                .fill(Color.primary.opacity(day == BriefPaths.todayDateString() ? 0.06 : 0.03))
                                .frame(height: dayRowHeight)
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 1)
                                }
                        }
                    }

                    let range = span.yRange(in: Double(timelineHeight))
                    spanBar(span, tint: tint)
                        .frame(width: max(14, laneWidth - 28), height: CGFloat(range.height))
                        .offset(y: CGFloat(range.y))
                }
                .frame(height: timelineHeight, alignment: .top)
            }
            .opacity(dimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.22)) {
                if hovering {
                    hoveredID = span.id
                } else if hoveredID == span.id {
                    hoveredID = nil
                }
            }
        }
        .accessibilityLabel(accessibilityLabel(for: span))
        .accessibilityHint("打开任务详情")
    }

    private func laneHeader(_ span: WorkDaySpan) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: span.item.status.iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(span.item.status.chartTint)
                Text(span.item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Text(spanLabel(span))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func spanBar(_ span: WorkDaySpan, tint: Color) -> some View {
        let status = span.item.status
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(barFill(status: status, tint: tint))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(barStroke(status: status, tint: tint), lineWidth: 1)
                }
            if status == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.bottom, 4)
            } else if status == .inProgress {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.bottom, 5)
            }
        }
    }

    private func barFill(status: WorkStatus, tint: Color) -> Color {
        switch status {
        case .inProgress: return tint.opacity(0.92)
        case .pending: return tint.opacity(0.55)
        case .completed: return Color.green.opacity(0.55)
        case .cancelled: return Color.secondary.opacity(0.22)
        }
    }

    private func barStroke(status: WorkStatus, tint: Color) -> Color {
        switch status {
        case .inProgress: return tint
        case .pending: return tint.opacity(0.85)
        case .completed: return Color.green.opacity(0.9)
        case .cancelled: return Color.secondary.opacity(0.7)
        }
    }

    private func spanLabel(_ span: WorkDaySpan) -> String {
        let days = span.spanDayCount
        let statusShort: String = switch span.item.status {
        case .inProgress: "进行"
        case .pending: "待办"
        case .completed: "完成"
        case .cancelled: "完成"
        }
        if days <= 1 {
            return "\(statusShort) · 1天"
        }
        return "\(statusShort) · \(days)天"
    }

    private func dateRangeLabel(_ span: WorkDaySpan) -> String {
        let start = span.startDay.count >= 10 ? String(span.startDay.dropFirst(5)) : span.startDay
        let end = span.endDay == BriefPaths.todayDateString()
            ? "今天"
            : (span.endDay.count >= 10 ? String(span.endDay.dropFirst(5)) : span.endDay)
        return "\(start) → \(end)"
    }

    private func accessibilityLabel(for span: WorkDaySpan) -> String {
        "\(span.item.status.title)，\(span.item.title)，\(dateRangeLabel(span))，\(span.spanDayCount) 天"
    }

    static func laneTint(for itemID: String, status: WorkStatus) -> Color {
        if status == .completed {
            return .green
        }
        let palette: [Color] = [
            .blue, .teal, .orange, .indigo, .cyan, .mint, .purple, .pink,
        ]
        var hash = 0
        for scalar in itemID.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }
}

private extension WorkStatus {
    var chartTint: Color {
        switch self {
        case .pending: .secondary
        case .inProgress: .accentColor
        case .completed: .green
        case .cancelled: .secondary
        }
    }
}
