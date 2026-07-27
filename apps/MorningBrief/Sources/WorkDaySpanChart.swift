import SwiftUI

/// Single work-ledger surface: date×task span chart with status chrome and hover detail.
struct WorkDaySpanChart: View {
    let spans: [WorkDaySpan]
    let onSelect: (WorkItem) -> Void

    @State private var hoveredID: String?
    @State private var statusFilter: Set<WorkStatus> = []

    private let minDayRowHeight: CGFloat = 22
    private let maxDayRowHeight: CGFloat = 36
    private let dateGutter: CGFloat = 40
    private let minLaneWidth: CGFloat = 64
    private let maxLaneWidth: CGFloat = 120
    private let headerHeight: CGFloat = 48
    private let laneSpacing: CGFloat = 6

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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            statusLegend
            if spans.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    let layout = chartLayout(in: geo.size)
                    ZStack(alignment: .topLeading) {
                        chartCanvas(layout: layout, size: geo.size)
                        if let span = hoveredSpan {
                            hoverCard(span)
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.15), value: hoveredID)
    }

    private var emptyState: some View {
        Text("暂无任务跨度")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, DS.Space.md)
    }

    private var statusLegend: some View {
        HStack(spacing: 6) {
            Text("\(spans.count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(statusOrder, id: \.self) { status in
                        let count = counts[status, default: 0]
                        statusChip(status, count: count)
                    }
                }
            }
            if !statusFilter.isEmpty {
                Button("全部") {
                    statusFilter = []
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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

    private struct ChartLayout {
        let dayRowHeight: CGFloat
        let laneWidth: CGFloat
        let timelineHeight: CGFloat
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let fillsHeight: Bool
        let fillsWidth: Bool
    }

    private func chartLayout(in size: CGSize) -> ChartLayout {
        let dayCount = max(chartDays.count, 1)
        let laneCount = max(visibleSpans.count, 1)
        let availableTimeline = max(minDayRowHeight, size.height - headerHeight)
        let naturalTimeline = CGFloat(dayCount) * minDayRowHeight
        let fillsHeight = naturalTimeline <= availableTimeline
        let dayRowHeight: CGFloat
        let timelineHeight: CGFloat
        if fillsHeight {
            dayRowHeight = min(maxDayRowHeight, availableTimeline / CGFloat(dayCount))
            timelineHeight = dayRowHeight * CGFloat(dayCount)
        } else {
            dayRowHeight = minDayRowHeight
            timelineHeight = naturalTimeline
        }

        let lanesBudget = max(0, size.width - dateGutter - DS.Space.sm)
        let spacingTotal = laneSpacing * CGFloat(max(laneCount - 1, 0))
        let naturalLanes = CGFloat(laneCount) * minLaneWidth + spacingTotal
        let fillsWidth = naturalLanes <= lanesBudget
        let laneWidth: CGFloat
        if fillsWidth, laneCount > 0 {
            let raw = (lanesBudget - spacingTotal) / CGFloat(laneCount)
            laneWidth = min(maxLaneWidth, max(minLaneWidth, raw))
        } else {
            laneWidth = minLaneWidth
        }

        let contentWidth = dateGutter
            + CGFloat(laneCount) * laneWidth
            + spacingTotal
            + DS.Space.sm
        let contentHeight = headerHeight + timelineHeight
        return ChartLayout(
            dayRowHeight: dayRowHeight,
            laneWidth: laneWidth,
            timelineHeight: timelineHeight,
            contentWidth: max(contentWidth, size.width),
            contentHeight: fillsHeight ? max(contentHeight, size.height) : contentHeight,
            fillsHeight: fillsHeight,
            fillsWidth: fillsWidth
        )
    }

    private func chartCanvas(layout: ChartLayout, size: CGSize) -> some View {
        let canvas = HStack(alignment: .top, spacing: 0) {
            dateScale(dayRowHeight: layout.dayRowHeight)
                .frame(width: dateGutter)
            HStack(alignment: .top, spacing: laneSpacing) {
                ForEach(visibleSpans) { span in
                    laneColumn(span, layout: layout)
                        .frame(width: layout.laneWidth)
                }
            }
            .frame(maxWidth: layout.fillsWidth ? .infinity : nil, alignment: .leading)
            if layout.fillsWidth {
                Spacer(minLength: 0)
            }
        }
        .frame(
            width: layout.fillsWidth ? size.width : layout.contentWidth,
            height: layout.fillsHeight ? size.height : layout.contentHeight,
            alignment: .topLeading
        )
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            canvas
        }
        .frame(width: size.width, height: size.height)
    }

    private func dateScale(dayRowHeight: CGFloat) -> some View {
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

    private func laneColumn(_ span: WorkDaySpan, layout: ChartLayout) -> some View {
        let status = span.item.status
        let tint = Self.laneTint(for: span.item.id, status: status)
        let dimmed = hoveredID != nil && hoveredID != span.id
        let range = span.yRange(in: Double(layout.timelineHeight))
        return Button {
            onSelect(span.item)
        } label: {
            VStack(spacing: 0) {
                laneHeader(span)
                    .frame(height: headerHeight)

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(Array(chartDays.enumerated()), id: \.offset) { _, day in
                            Rectangle()
                                .fill(Color.primary.opacity(day == BriefPaths.todayDateString() ? 0.06 : 0.025))
                                .frame(height: layout.dayRowHeight)
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 1)
                                }
                        }
                    }

                    spanBar(span, tint: tint)
                        .frame(width: max(12, layout.laneWidth - 20), height: max(layout.dayRowHeight - 4, CGFloat(range.height) - 4))
                        .padding(.top, 2)
                        .offset(y: CGFloat(range.y))
                }
                .frame(height: layout.timelineHeight, alignment: .top)
                .clipped()
            }
            .opacity(dimmed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = span.id
            } else if hoveredID == span.id {
                hoveredID = nil
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
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

    private func hoverCard(_ span: WorkDaySpan) -> some View {
        let item = span.item
        return Button {
            onSelect(item)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
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
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .strokeBorder(item.status.chartTint.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
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
