import Foundation

enum BriefStatus: String, Codable, CaseIterable {
    case idle
    case fetching
    case synthesizing
    case running
    case ready
    case degraded
    case failed
    case error
    case locked

    var iconName: String {
        switch self {
        case .idle: "sun.horizon"
        case .fetching, .synthesizing, .running: "arrow.triangle.2.circlepath"
        case .ready: "newspaper"
        case .degraded: "exclamationmark.triangle"
        case .locked: "hourglass"
        case .failed, .error: "xmark.circle"
        }
    }

    init(runStatus raw: String) {
        switch raw.lowercased() {
        case "fetching": self = .fetching
        case "synthesizing": self = .synthesizing
        case "ready": self = .ready
        case "degraded": self = .degraded
        case "failed": self = .failed
        case "locked": self = .locked
        case "idle": self = .idle
        default: self = .idle
        }
    }
}

enum SectionStatus: String, Codable {
    case ok, empty, failed, partial, synthesized, unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased() ?? ""
        self = SectionStatus(rawValue: raw) ?? .unknown
    }
}

struct BriefSection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let bodyMd: String
    let sourceIds: [String]
    let status: SectionStatus

    enum CodingKeys: String, CodingKey {
        case id, title, kind
        case bodyMd = "body_md"
        case sourceIds = "source_ids"
        case status
    }

    var body: String { bodyMd }

    /// True when the section carries something worth reading (non-empty body and
    /// not an empty/failed placeholder). Drives hero vs. empty-state decisions.
    var hasContent: Bool {
        guard !bodyMd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch status {
        case .ok, .partial, .synthesized: return true
        case .empty, .failed, .unknown: return false
        }
    }
}

/// One must-read row inside the hero. Optional `sectionId` links to a full
/// section for in-panel expansion; optional `url` opens externally.
struct HeroMustRead: Codable, Hashable {
    let title: String
    let summary: String?
    let sectionId: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case title, summary
        case sectionId = "section_id"
        case url
    }
}

/// The above-the-fold conclusion: a headline plus up to three must-reads.
struct BriefHero: Codable, Hashable {
    let headline: String
    let mustReads: [HeroMustRead]

    enum CodingKeys: String, CodingKey {
        case headline
        case mustReads = "must_reads"
    }

    var hasContent: Bool {
        !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mustReads.isEmpty
    }
}

struct BriefSourceChip: Identifiable, Hashable {
    let id: String
    let name: String
    let status: SectionStatus
}

struct BriefDocument: Codable {
    let date: String
    let generatedAt: String
    let status: String
    let sections: [BriefSection]
    let hero: BriefHero?
    let meta: [String: FlexibleJSON]?

    enum CodingKeys: String, CodingKey {
        case date
        case generatedAt = "generated_at"
        case status
        case sections
        case hero
        case meta
    }

    /// Sections that actually carry readable content.
    var readableSections: [BriefSection] {
        sections.filter(\.hasContent)
    }

    /// True when there is something to show above the empty-state one-liner:
    /// a populated hero or at least one readable section.
    var hasReadableContent: Bool {
        (hero?.hasContent ?? false) || !readableSections.isEmpty
    }

    var generatedAtDate: Date? {
        BriefDateParser.iso8601.date(from: generatedAt)
            ?? BriefDateParser.iso8601Fractional.date(from: generatedAt)
    }

    /// Staleness threshold in hours from pipeline meta, if present.
    var stalenessHours: Double? {
        if case .number(let v)? = meta?["staleness_hours"] { return v }
        return nil
    }

    /// Synthesis mode badge from pipeline meta (agent/degraded/skipped/cached/schema_fallback/none).
    var synthBadge: String? {
        if case .string(let v)? = meta?["synth"] { return v }
        return nil
    }
}

struct RunDocument: Codable {
    let status: String?
    let sources: [String: RunSourceStatus]?
    let errors: [String]?

    var briefStatus: BriefStatus {
        BriefStatus(runStatus: status ?? "idle")
    }

    /// Chips derived from fetch-time source statuses in run.json (id as name; run.json has no title).
    var sourceChips: [BriefSourceChip] {
        guard let sources else { return [] }
        return sources.keys.sorted().map { id in
            let raw = (sources[id]?.status ?? "").lowercased()
            return BriefSourceChip(id: id, name: id, status: SectionStatus(rawValue: raw) ?? .unknown)
        }
    }
}

struct RunSourceStatus: Codable {
    let status: String?
}

/// Accept arbitrary JSON values in meta without failing decode.
enum FlexibleJSON: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: FlexibleJSON])
    case array([FlexibleJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([String: FlexibleJSON].self) { self = .object(v); return }
        if let v = try? container.decode([FlexibleJSON].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

enum BriefDateParser {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum WorkStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case inProgress = "in_progress"
    case completed
    /// Legacy decode only — cancelled writes are retired; use delete instead.
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: "待处理"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .cancelled: "已取消"
        }
    }

    var iconName: String {
        switch self {
        case .pending: "circle"
        case .inProgress: "circle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    /// Lower = earlier lane in the span chart (active work first).
    var spanLanePriority: Int {
        switch self {
        case .inProgress: 0
        case .pending: 1
        case .completed: 2
        case .cancelled: 3
        }
    }

    static var chartFilterStatuses: [WorkStatus] {
        [.inProgress, .pending, .completed]
    }
}

struct WorkEvent: Codable, Identifiable, Hashable {
    let sequence: Int
    let eventId: String
    let itemId: String
    let kind: String
    let actor: String
    let occurredAt: String
    let payload: [String: FlexibleJSON]
    let reason: String?
    let evidence: [String]
    let idempotencyKey: String?
    let targetEventId: String?

    var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case sequence
        case eventId = "event_id"
        case itemId = "item_id"
        case kind, actor
        case occurredAt = "occurred_at"
        case payload, reason, evidence
        case idempotencyKey = "idempotency_key"
        case targetEventId = "target_event_id"
    }

    var summary: String {
        switch kind {
        case "created":
            return "创建任务"
        case "edited":
            return "更新了任务信息"
        case "status_changed":
            if case .string(let status)? = payload["status"],
               let workStatus = WorkStatus(rawValue: status) {
                return "状态更新为\(workStatus.title)"
            }
            return "更新了状态"
        case "progress_added":
            if case .string(let text)? = payload["text"] { return text }
            return "追加了进展"
        case "progress_edited":
            if case .string(let text)? = payload["text"] { return "修订进展：\(text)" }
            return "修订了进展"
        case "tombstoned":
            return "已删除（可撤销）"
        case "reverted":
            return "撤销了一次变更"
        default:
            return kind
        }
    }

    var occurredAtDate: Date? {
        BriefDateParser.iso8601Fractional.date(from: occurredAt)
            ?? BriefDateParser.iso8601.date(from: occurredAt)
    }
}

struct WorkItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let status: WorkStatus
    let createdAt: String
    let updatedAt: String
    let version: Int
    let terminalDate: String?
    let events: [WorkEvent]

    enum CodingKeys: String, CodingKey {
        case id, title, detail, status, version, events
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case terminalDate = "terminal_date"
    }

    var lastEventDate: Date? {
        BriefDateParser.iso8601Fractional.date(from: updatedAt)
            ?? BriefDateParser.iso8601.date(from: updatedAt)
    }

    var lastProgress: String? {
        for event in events.reversed() where event.kind == "progress_added" && !isEventReverted(event) {
            if case .string(let text)? = event.payload["text"] { return text }
        }
        return nil
    }

    var createdAtDate: Date? {
        BriefDateParser.iso8601Fractional.date(from: createdAt)
            ?? BriefDateParser.iso8601.date(from: createdAt)
    }

    /// Wall-clock age chrome: created → now (active) or → last update when terminal.
    var wallClockDurationLabel: String? {
        guard let start = createdAtDate else { return nil }
        let end: Date
        if status == .completed || status == .cancelled {
            end = lastEventDate ?? start
        } else {
            end = Date()
        }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return Self.formatDuration(seconds)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "已持续 \(days) 天 \(hours) 小时" : "已持续 \(days) 天"
        }
        if hours > 0 {
            return minutes > 0 ? "已持续 \(hours) 小时 \(minutes) 分" : "已持续 \(hours) 小时"
        }
        if minutes > 0 {
            return "已持续 \(minutes) 分"
        }
        return "已持续不到 1 分"
    }

    func isEventReverted(_ event: WorkEvent) -> Bool {
        events.contains { $0.kind == "reverted" && $0.targetEventId == event.eventId }
    }

    func summary(for target: WorkEvent) -> String {
        if target.kind == "status_changed",
           case .string(let rawStatus)? = target.payload["status"],
           let nextStatus = WorkStatus(rawValue: rawStatus) {
            var previousStatus = WorkStatus.pending
            for event in events {
                if event.eventId == target.eventId { break }
                guard event.kind == "status_changed", !isEventReverted(event),
                      case .string(let raw)? = event.payload["status"],
                      let status = WorkStatus(rawValue: raw) else {
                    continue
                }
                previousStatus = status
            }
            return "状态：\(previousStatus.title) → \(nextStatus.title)"
        }
        if target.kind == "edited" {
            let fields = [
                target.payload["title"] == nil ? nil : "标题",
                target.payload["detail"] == nil ? nil : "说明",
            ].compactMap { $0 }
            return fields.isEmpty ? target.summary : "更新：\(fields.joined(separator: "、"))"
        }
        return target.summary
    }

    /// One continuous text value for native selection across the title, detail,
    /// and every timeline event. SwiftUI cannot extend a selection across
    /// separate `Text` views, so the detail screen renders this as one `Text`.
    func selectionTranscript(eventTime: (WorkEvent) -> String) -> String {
        var blocks = [title]
        if !detail.isEmpty {
            blocks.append(detail)
        }

        for event in events {
            let actor = switch event.actor {
            case "human": "你"
            case "agent": "Agent"
            default: "系统"
            }
            let time = eventTime(event)
            let heading = time.isEmpty ? actor : "\(actor) · \(time)"
            let revertedPrefix = isEventReverted(event) ? "[已撤销] " : ""
            var lines = [heading, "\(revertedPrefix)\(summary(for: event))"]
            if let reason = event.reason, !reason.isEmpty {
                lines.append("理由：\(reason)")
            }
            if !event.evidence.isEmpty {
                lines.append("证据：\(event.evidence.joined(separator: " · "))")
            }
            blocks.append(lines.joined(separator: "\n"))
        }

        blocks.append("当前")
        return blocks.joined(separator: "\n\n")
    }
}

struct WorkHistoryDay: Codable, Identifiable, Hashable {
    let date: String
    let items: [WorkItem]

    var id: String { date }
    var completed: [WorkItem] { items.filter { $0.status == .completed } }
}

struct LatestReversible: Codable, Hashable {
    let event: WorkEvent
    let itemId: String
    let expectedVersion: Int

    enum CodingKeys: String, CodingKey {
        case event
        case itemId = "item_id"
        case expectedVersion = "expected_version"
    }
}

struct WorkDocument: Codable {
    let schemaVersion: Int
    let date: String
    let generatedAt: String
    let readOnly: Bool
    let items: [WorkItem]
    let recentHistory: [WorkHistoryDay]
    let latestAgentEvent: WorkEvent?
    let latestReversible: LatestReversible?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case generatedAt = "generated_at"
        case readOnly = "read_only"
        case items
        case recentHistory = "recent_history"
        case latestAgentEvent = "latest_agent_event"
        case latestReversible = "latest_reversible"
    }

    var pending: [WorkItem] { items.filter { $0.status == .pending } }
    var inProgress: [WorkItem] { items.filter { $0.status == .inProgress } }
    var completedToday: [WorkItem] {
        items.filter { $0.status == .completed && $0.terminalDate == date }
    }
    var allItems: [WorkItem] {
        items + recentHistory.flatMap(\.items)
    }

    /// Prefer server-published `latest_reversible` (needed after tombstone hide).
    var latestReversibleEvent: WorkEvent? {
        if let latestReversible { return latestReversible.event }
        let events = allItems.flatMap(\.events)
        let revertedIDs = Set(events.compactMap { $0.kind == "reverted" ? $0.targetEventId : nil })
        return events
            .filter {
                !revertedIDs.contains($0.eventId)
                    && [
                        "created",
                        "edited",
                        "status_changed",
                        "progress_added",
                        "progress_edited",
                        "tombstoned",
                    ].contains($0.kind)
            }
            .max { $0.sequence < $1.sequence }
    }

    /// Mixed day river: mutation events for the projection day, newest-first.
    var dayTimeline: [WorkTimelineEntry] {
        let day = self.date
        var entries: [WorkTimelineEntry] = []
        for item in items {
            for event in item.events {
                guard !item.isEventReverted(event) else { continue }
                guard [
                    "created",
                    "edited",
                    "status_changed",
                    "progress_added",
                    "tombstoned",
                ].contains(event.kind) else { continue }
                guard let occurred = event.occurredAtDate else { continue }
                let eventDay = BriefPaths.dayString(for: occurred)
                guard eventDay == day else { continue }
                entries.append(
                    WorkTimelineEntry(
                        id: event.eventId,
                        event: event,
                        item: item
                    )
                )
            }
        }
        return entries.sorted { $0.event.sequence > $1.event.sequence }
    }

    /// Active today + completed items from `recent_history`.
    var chartSourceItems: [WorkItem] {
        var seen = Set<String>()
        var result: [WorkItem] = []
        for item in items where item.status != .cancelled {
            if seen.insert(item.id).inserted {
                result.append(item)
            }
        }
        for group in recentHistory {
            for item in group.items where item.status != .cancelled {
                if seen.insert(item.id).inserted {
                    result.append(item)
                }
            }
        }
        return result
    }

    /// Per-task colored spans for the 2D chart (Y = calendar days, X = lanes).
    /// Includes recent completed work from history so they stay visible on the chart.
    func daySpans(now: Date = Date()) -> [WorkDaySpan] {
        let viewDay = date
        var drafts: [(item: WorkItem, startDay: String, endDay: String, isOpen: Bool)] = []
        for item in chartSourceItems {
            guard item.belongsOnSpanChart(viewDay: viewDay) else { continue }
            guard let created = item.createdAtDate else { continue }
            let startDay = BriefPaths.dayString(for: created)
            let isOpen = item.status == .pending || item.status == .inProgress
            let rawEnd: String
            if isOpen {
                rawEnd = viewDay
            } else if let terminal = item.terminalDate {
                rawEnd = terminal
            } else if let last = item.lastEventDate {
                rawEnd = BriefPaths.dayString(for: last)
            } else {
                rawEnd = startDay
            }
            // Clip to the viewed day so we don't paint into the future.
            let endDay = min(rawEnd, viewDay)
            let clampedStart = min(startDay, endDay)
            drafts.append((item, clampedStart, endDay, isOpen))
        }
        guard !drafts.isEmpty else { return [] }

        let rangeEndDay = viewDay
        let rangeStartDay = drafts.map(\.startDay).min() ?? viewDay

        let ordered = drafts.sorted {
            let p0 = $0.item.status.spanLanePriority
            let p1 = $1.item.status.spanLanePriority
            if p0 != p1 { return p0 < p1 }
            if $0.startDay != $1.startDay { return $0.startDay < $1.startDay }
            if $0.endDay != $1.endDay { return $0.endDay > $1.endDay }
            return $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
        }
        return ordered.enumerated().map { index, draft in
            WorkDaySpan(
                id: draft.item.id,
                item: draft.item,
                startDay: draft.startDay,
                endDay: draft.endDay,
                rangeStartDay: rangeStartDay,
                rangeEndDay: rangeEndDay,
                isOpen: draft.isOpen,
                laneIndex: index
            )
        }
    }

    /// Per-day active span counts for a contribution-style calendar ending at `endDay`.
    func spanActivityCounts(endingAt endDay: String, weeks: Int = 13) -> [String: Int] {
        guard weeks > 0,
              let windowStart = BriefPaths.dayString(byAddingDays: -(weeks * 7 - 1), to: endDay)
        else { return [:] }

        var counts: [String: Int] = [:]
        for day in BriefPaths.dayStrings(from: windowStart, through: endDay) {
            counts[day] = 0
        }

        for item in chartSourceItems {
            guard let created = item.createdAtDate else { continue }
            let itemStart = BriefPaths.dayString(for: created)
            let isOpen = item.status == .pending || item.status == .inProgress
            let itemEnd: String
            if isOpen {
                itemEnd = endDay
            } else if let terminal = item.terminalDate {
                itemEnd = terminal
            } else if let last = item.lastEventDate {
                itemEnd = BriefPaths.dayString(for: last)
            } else {
                itemEnd = itemStart
            }
            let clippedStart = max(itemStart, windowStart)
            let clippedEnd = min(itemEnd, endDay)
            guard clippedStart <= clippedEnd else { continue }
            for day in BriefPaths.dayStrings(from: clippedStart, through: clippedEnd) {
                counts[day, default: 0] += 1
            }
        }
        return counts
    }

}

struct WorkTimelineEntry: Identifiable, Hashable {
    let id: String
    let event: WorkEvent
    let item: WorkItem
}

/// One task's continuous span across calendar days (not clock hours, not event nodes).
struct WorkDaySpan: Identifiable, Hashable {
    let id: String
    let item: WorkItem
    /// Inclusive `yyyy-MM-dd` start of the task's life (created day).
    let startDay: String
    /// Inclusive `yyyy-MM-dd` end (terminal day, or viewed day if still open).
    let endDay: String
    /// Shared chart window (top → bottom).
    let rangeStartDay: String
    let rangeEndDay: String
    let isOpen: Bool
    var laneIndex: Int = 0

    /// Inclusive day count of this task's span (before chart clipping).
    var spanDayCount: Int {
        max(1, (BriefPaths.dayOffset(from: startDay, to: endDay) ?? 0) + 1)
    }

    /// Day keys drawn on the Y axis, oldest at top.
    var chartDays: [String] {
        BriefPaths.dayStrings(from: rangeStartDay, through: rangeEndDay)
    }

    /// Vertical layout in day rows: top = older dates, bottom = viewed day.
    func yRange(in chartHeight: Double) -> (y: Double, height: Double) {
        let days = chartDays
        guard !days.isEmpty, chartHeight > 0 else { return (0, chartHeight) }
        let row = chartHeight / Double(days.count)
        let startIdx = days.firstIndex(of: max(startDay, rangeStartDay)) ?? 0
        let endIdx = days.firstIndex(of: min(endDay, rangeEndDay)) ?? (days.count - 1)
        let lo = min(startIdx, endIdx)
        let hi = max(startIdx, endIdx)
        return (Double(lo) * row, max(row, Double(hi - lo + 1) * row))
    }
}

extension WorkItem {
    func belongsOnDayChart(day: String) -> Bool {
        if status == .pending || status == .inProgress { return true }
        if terminalDate == day { return true }
        return events.contains { event in
            guard !isEventReverted(event) else { return false }
            guard let occurred = event.occurredAtDate else { return false }
            return BriefPaths.dayString(for: occurred) == day
        }
    }

    /// Span chart includes active work plus completed items already in the projection.
    func belongsOnSpanChart(viewDay: String) -> Bool {
        if status == .cancelled { return false }
        if status == .pending || status == .inProgress { return true }
        if status == .completed {
            if let terminalDate, terminalDate <= viewDay { return true }
            return belongsOnDayChart(day: viewDay)
        }
        return belongsOnDayChart(day: viewDay)
    }
}

struct ClaudeSessionMatch: Codable, Hashable {
    let id: String
    let project: String
    let sourceFile: String
    let modifiedAt: String
    let matchedAnchors: [String]
    let confidence: String
    let fileCount: Int
    let subagentCount: Int

    enum CodingKeys: String, CodingKey {
        case id, project, confidence
        case sourceFile = "source_file"
        case modifiedAt = "modified_at"
        case matchedAnchors = "matched_anchors"
        case fileCount = "file_count"
        case subagentCount = "subagent_count"
    }
}

struct SessionTodoMatch: Codable, Identifiable, Hashable {
    let itemId: String
    let title: String
    let confidence: Double
    let reason: String

    var id: String { itemId }

    enum CodingKeys: String, CodingKey {
        case title, confidence, reason
        case itemId = "item_id"
    }
}

enum SessionProposalAction: String, Codable {
    case add
    case edit
    case note
    case status

    var title: String {
        switch self {
        case .add: "新增 Todo"
        case .edit: "编辑 Todo"
        case .note: "追加进展"
        case .status: "更新状态"
        }
    }
}

struct SessionTodoProposal: Codable, Identifiable, Hashable {
    let proposalId: String
    let action: SessionProposalAction
    let reason: String
    let evidence: [String]
    let itemId: String?
    let itemTitle: String?
    let expectedVersion: Int?
    let title: String?
    let detail: String?
    let text: String?
    let status: String?

    var id: String { proposalId }

    enum CodingKeys: String, CodingKey {
        case action, reason, evidence, title, detail, text, status
        case proposalId = "proposal_id"
        case itemId = "item_id"
        case itemTitle = "item_title"
        case expectedVersion = "expected_version"
    }

    var summary: String {
        switch action {
        case .add:
            return title ?? "新增未命名 Todo"
        case .edit:
            let fields = [
                title.map { "标题：\($0)" },
                detail.map { "说明：\($0)" },
            ].compactMap { $0 }
            return fields.joined(separator: "\n")
        case .note:
            return text ?? "追加进展"
        case .status:
            let localized = status.flatMap { WorkStatus(rawValue: $0)?.title } ?? status ?? "未知"
            return "状态 → \(localized)"
        }
    }
}

struct SessionAnalysis: Codable, Identifiable {
    let schemaVersion: Int
    let analysisId: String
    let createdAt: String
    let session: ClaudeSessionMatch
    let summary: String
    let todoMatches: [SessionTodoMatch]
    let proposals: [SessionTodoProposal]
    let appliedAt: String?

    var id: String { analysisId }

    enum CodingKeys: String, CodingKey {
        case session, summary, proposals
        case schemaVersion = "schema_version"
        case analysisId = "analysis_id"
        case createdAt = "created_at"
        case todoMatches = "todo_matches"
        case appliedAt = "applied_at"
    }
}

struct SessionApplyResult: Codable {
    let analysisId: String
    let appliedCount: Int
    let duplicate: Bool
    let events: [WorkEvent]
    let items: [WorkItem]
    let appliedAt: String?

    enum CodingKeys: String, CodingKey {
        case duplicate, events, items
        case analysisId = "analysis_id"
        case appliedCount = "applied_count"
        case appliedAt = "applied_at"
    }
}

/// One recent session (Claude / Codex / Cursor) for the Agent picker.
struct RecentSession: Codable, Identifiable, Hashable {
    /// Composite id: ``claude:<uuid>`` / ``codex:<uuid>`` / ``cursor:<uuid>``.
    let id: String
    /// `claude` | `codex` | `cursor`
    let source: String
    let project: String
    let sourceFile: String
    let modifiedAt: String
    let subagentCount: Int
    /// Cheap JSONL snippet (first user/summary line). Fallback while agent summary is pending.
    let preview: String
    /// Latest substantive user asks (oldest → newest) for expand-panel evidence.
    let recentAsks: [String]
    /// Persisted agent CLI summary for this session fingerprint; nil until generated.
    let summary: String?
    /// Fuller expand-panel brief from the same summarize pass; nil until generated.
    let detail: String?
    /// `ready` | `pending` | `failed` from briefctl assistant sessions/summarize.
    let summaryStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, source, project, preview, summary, detail
        case sourceFile = "source_file"
        case modifiedAt = "modified_at"
        case subagentCount = "subagent_count"
        case summaryStatus = "summary_status"
        case recentAsks = "recent_asks"
    }

    init(
        id: String,
        source: String = "claude",
        project: String,
        sourceFile: String,
        modifiedAt: String,
        subagentCount: Int,
        preview: String,
        recentAsks: [String] = [],
        summary: String?,
        detail: String? = nil,
        summaryStatus: String?
    ) {
        self.id = id
        self.source = source
        self.project = project
        self.sourceFile = sourceFile
        self.modifiedAt = modifiedAt
        self.subagentCount = subagentCount
        self.preview = preview
        self.recentAsks = recentAsks
        self.summary = summary
        self.detail = detail
        self.summaryStatus = summaryStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "claude"
        project = try container.decode(String.self, forKey: .project)
        sourceFile = try container.decode(String.self, forKey: .sourceFile)
        modifiedAt = try container.decode(String.self, forKey: .modifiedAt)
        subagentCount = try container.decode(Int.self, forKey: .subagentCount)
        preview = try container.decode(String.self, forKey: .preview)
        recentAsks = try container.decodeIfPresent([String].self, forKey: .recentAsks) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        summaryStatus = try container.decodeIfPresent(String.self, forKey: .summaryStatus)
    }

    var sourceTitle: String {
        switch source {
        case "codex": "Codex"
        case "cursor": "Cursor"
        default: "Claude"
        }
    }

    var supportsAnalyze: Bool { source == "claude" }

    var modifiedAtDate: Date? {
        BriefDateParser.iso8601Fractional.date(from: modifiedAt)
            ?? BriefDateParser.iso8601.date(from: modifiedAt)
    }

    /// Prefer the persisted agent summary; never dump long raw transcript previews as the title.
    var displayTitle: String {
        if let summary, !summary.isEmpty { return summary }
        if summaryStatus == "pending" { return "正在生成摘要…" }
        if summaryStatus == "failed", !preview.isEmpty { return preview }
        if !preview.isEmpty { return preview }
        return id
    }
}

struct RecentSessionList: Codable {
    let sessions: [RecentSession]
}

struct RecentSessionSummarizeResult: Codable {
    let sessions: [RecentSession]
    let summarized: Int?
    let skipped: Int?
    let failed: Int?
}

enum BriefPaths {
    static let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MorningBrief/briefs", isDirectory: true)

    /// Fallback timezone used before briefctl reports the configured local day.
    /// Work projection refreshes omit --date for "today", so Python remains the
    /// authority when the configured timezone differs from this fallback.
    static let dayTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = dayTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    /// `yyyy-MM-dd` day key for the given date in `dayTimeZone`.
    static func dayString(for date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    static func startOfDay(forDateString value: String) -> Date? {
        guard let day = dayFormatter.date(from: value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dayTimeZone
        return calendar.startOfDay(for: day)
    }

    static func endOfDay(forDateString value: String) -> Date? {
        guard let start = startOfDay(forDateString: value) else { return nil }
        return start.addingTimeInterval(24 * 60 * 60 - 1)
    }

    /// `yyyy-MM-dd` by adding whole days in `dayTimeZone`.
    static func dayString(byAddingDays days: Int, to value: String) -> String? {
        guard let start = startOfDay(forDateString: value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dayTimeZone
        guard let shifted = calendar.date(byAdding: .day, value: days, to: start) else {
            return nil
        }
        return dayString(for: shifted)
    }

    /// Whole-day offset from `from` to `to` (`to - from`). Nil if either key is invalid.
    static func dayOffset(from: String, to: String) -> Int? {
        guard let a = startOfDay(forDateString: from),
              let b = startOfDay(forDateString: to) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dayTimeZone
        return calendar.dateComponents([.day], from: a, to: b).day
    }

    /// Inclusive day keys from `from` through `through` (ascending).
    static func dayStrings(from: String, through: String) -> [String] {
        guard from <= through,
              let start = startOfDay(forDateString: from),
              startOfDay(forDateString: through) != nil else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dayTimeZone
        var days: [String] = []
        var cursor = start
        let endKey = through
        while true {
            let key = dayString(for: cursor)
            days.append(key)
            if key >= endKey { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            // Safety cap for pathological spans; UI scrolls within this window.
            if days.count > 366 { break }
        }
        return days
    }

    /// Today's day key (in `dayTimeZone`).
    static func todayDateString() -> String {
        dayString(for: Date())
    }

    static func dayDirectory(for date: Date = Date()) -> URL {
        appSupport.appendingPathComponent(dayString(for: date), isDirectory: true)
    }

    static func dayDirectory(forDateString dateString: String) -> URL {
        appSupport.appendingPathComponent(dateString, isDirectory: true)
    }

    /// True if `value` is a valid `yyyy-MM-dd` day key.
    static func isDayString(_ value: String) -> Bool {
        value.count == 10 && dayFormatter.date(from: value) != nil
    }

    /// Day keys (`yyyy-MM-dd`) that have a folder under `appSupport`, sorted ascending.
    static func availableDates() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { url -> String? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            return isDir && isDayString(name) ? name : nil
        }.sorted()
    }

    static func briefJSON(in directory: URL) -> URL {
        directory.appendingPathComponent("brief.json")
    }

    static func runJSON(in directory: URL) -> URL {
        directory.appendingPathComponent("run.json")
    }

    static func workJSON(in directory: URL) -> URL {
        directory.appendingPathComponent("work.json")
    }
}
