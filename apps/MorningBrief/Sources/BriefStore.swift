import AppKit
import Foundation
import SwiftUI

@MainActor
final class BriefStore: ObservableObject {
    @Published private(set) var status: BriefStatus = .idle
    @Published private(set) var brief: BriefDocument?
    @Published private(set) var run: RunDocument?
    @Published private(set) var work: WorkDocument?
    @Published private(set) var displayDate: String = ""
    @Published private(set) var isStale = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSynthesizing = false
    @Published private(set) var isDoctorRunning = false
    @Published private(set) var isWorkMutating = false
    @Published private(set) var sessionAnalysis: SessionAnalysis?
    @Published private(set) var locatedSession: ClaudeSessionMatch?
    @Published private(set) var recentSessions: [RecentSession] = []
    @Published private(set) var isSessionLocating = false
    @Published private(set) var isSessionAnalyzing = false
    @Published private(set) var isSessionApplying = false
    @Published private(set) var isSessionSummarizing = false

    /// Day currently being viewed (`yyyy-MM-dd`). Defaults to today in `BriefPaths.dayTimeZone`.
    @Published private(set) var selectedDate: String = BriefPaths.todayDateString()
    /// Day keys with artifacts on disk, sorted ascending.
    @Published private(set) var availableDates: [String] = []

    /// True while any pipeline command (fetch or synth) is running.
    var isBusy: Bool { isRefreshing || isSynthesizing }

    /// True when `selectedDate` is today; pipeline commands only operate on today.
    var isViewingToday: Bool { selectedDate == lastKnownToday }

    @Published var notice: String?
    @Published var errorMessage: String?

    private let runner = BriefctlRunner()
    private var watcher: BriefWatcher!
    private let decoder = JSONDecoder()
    private var noticeClearTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var workProjectionDatesInFlight = Set<String>()
    private var lastKnownToday = BriefPaths.todayDateString()

    private var dayDirectory: URL { BriefPaths.dayDirectory(forDateString: selectedDate) }

    /// Selectable days for navigation: available days plus today (even if empty), sorted ascending.
    private var navigableDates: [String] {
        var set = Set(availableDates)
        set.insert(lastKnownToday)
        return set.sorted()
    }

    var canSelectPreviousDate: Bool {
        guard let idx = navigableDates.firstIndex(of: selectedDate) else { return !navigableDates.isEmpty }
        return idx > 0
    }

    var canSelectNextDate: Bool {
        let dates = navigableDates
        guard let idx = dates.firstIndex(of: selectedDate) else { return !dates.isEmpty }
        return idx < dates.count - 1
    }

    init() {
        watcher = BriefWatcher { [weak self] in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        refreshAvailableDates()
        reloadFromDisk()
        watcher.watch(directory: dayDirectory)
        refreshWorkProjection()
    }

    deinit {
        watcher?.stop()
    }

    var statusIcon: String { status.iconName }

    private func refreshAvailableDates() {
        availableDates = BriefPaths.availableDates()
    }

    /// Switch the viewed day: reload from that day's dir and re-point the watcher.
    func select(date: String) {
        guard date != selectedDate else { return }
        selectedDate = date
        reloadFromDisk()
        watcher.watch(directory: dayDirectory)
        refreshWorkProjection()
    }

    /// Move to the previous (earlier) available day; stays put before the earliest.
    func selectPreviousDate() {
        let dates = navigableDates
        guard let idx = dates.firstIndex(of: selectedDate) else {
            if let first = dates.first { select(date: first) }
            return
        }
        guard idx > 0 else { return }
        select(date: dates[idx - 1])
    }

    /// Move to the next (later) available day; stays put past the latest.
    func selectNextDate() {
        let dates = navigableDates
        guard let idx = dates.firstIndex(of: selectedDate) else {
            if let last = dates.last { select(date: last) }
            return
        }
        guard idx < dates.count - 1 else { return }
        select(date: dates[idx + 1])
    }

    func reloadFromDisk() {
        let directory = dayDirectory
        displayDate = directory.lastPathComponent

        var loadedBrief: BriefDocument?
        let briefURL = BriefPaths.briefJSON(in: directory)
        if let data = try? Data(contentsOf: briefURL) {
            do {
                loadedBrief = try decoder.decode(BriefDocument.self, from: data)
            } catch {
                errorMessage = "brief.json 解析失败: \(error.localizedDescription)"
            }
        }
        brief = loadedBrief

        var runStatus: BriefStatus?
        var loadedRun: RunDocument?
        let runURL = BriefPaths.runJSON(in: directory)
        if let data = try? Data(contentsOf: runURL),
           let runDoc = try? decoder.decode(RunDocument.self, from: data) {
            loadedRun = runDoc
            runStatus = runDoc.briefStatus
        }
        run = loadedRun

        let workURL = BriefPaths.workJSON(in: directory)
        if let data = try? Data(contentsOf: workURL) {
            do {
                work = try decoder.decode(WorkDocument.self, from: data)
            } catch {
                work = nil
                errorMessage = "work.json 解析失败: \(error.localizedDescription)"
            }
        } else {
            work = nil
        }

        isStale = computeStaleness(for: loadedBrief)

        if isBusy {
            status = .running
        } else if let runStatus {
            status = runStatus
        } else if let loadedBrief {
            status = BriefStatus(runStatus: loadedBrief.status)
        } else {
            status = .idle
        }
    }

    /// Fetch-only refresh (no agent synthesis). Only operates on today.
    func refresh() {
        guard !isBusy, isViewingToday else { return }
        isRefreshing = true
        runCommand(.runFetchOnly) { [weak self] in self?.isRefreshing = false }
    }

    /// Synthesize the brief from already-fetched sources via the agent. Only operates on today.
    func synthesize() {
        guard !isBusy, isViewingToday else { return }
        isSynthesizing = true
        runCommand(.synth) { [weak self] in self?.isSynthesizing = false }
    }

    private func runCommand(_ command: BriefctlCommand, done: @escaping () -> Void) {
        status = .running
        errorMessage = nil
        noticeClearTask?.cancel()
        notice = "正在更新…"

        pipelineTask = Task {
            var succeeded = false
            var alreadyRunning = false
            var cancelled = false
            defer {
                done()
                // briefctl always writes today's folder; pick up any newly created day.
                refreshAvailableDates()
                if isViewingToday { reloadFromDisk() }
                if cancelled {
                    setTransientNotice("已取消")
                } else if alreadyRunning {
                    notice = "已在生成"
                } else if succeeded {
                    setTransientNotice("已更新")
                } else {
                    notice = nil
                }
            }
            do {
                let result = try await runner.run(command)
                if result.isAlreadyRunning {
                    alreadyRunning = true
                } else {
                    succeeded = true
                }
            } catch is CancellationError {
                cancelled = true
                status = isBusy ? .running : .idle
            } catch let error as BriefctlError {
                switch error {
                case .failed(let exitCode, _) where exitCode == 75:
                    alreadyRunning = true
                default:
                    errorMessage = error.localizedDescription
                    status = .error
                }
            } catch {
                errorMessage = error.localizedDescription
                status = .error
            }
        }
    }

    /// Cancel an in-flight fetch/synth pipeline command.
    func cancelPipeline() {
        pipelineTask?.cancel()
    }

    /// Show a short-lived notice (e.g. 「已更新」) that auto-clears after a beat.
    private func setTransientNotice(_ message: String) {
        notice = message
        noticeClearTask?.cancel()
        noticeClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if notice == message { notice = nil }
        }
    }

    func doctor() {
        guard !isDoctorRunning else { return }
        isDoctorRunning = true
        notice = nil
        errorMessage = nil
        Task {
            defer { isDoctorRunning = false }
            do {
                let result = try await runner.run(.doctor)
                notice = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshWorkProjection() {
        let requestedDate = selectedDate
        let requestingToday = requestedDate == lastKnownToday
        let requestKey = requestingToday ? "__today__" : requestedDate
        guard workProjectionDatesInFlight.insert(requestKey).inserted else { return }
        Task {
            defer { workProjectionDatesInFlight.remove(requestKey) }
            do {
                let result = try await runner.run(
                    .todoView(date: requestingToday ? nil : requestedDate, days: 7)
                )
                if requestingToday {
                    let document = try decoder.decode(
                        WorkDocument.self,
                        from: Data(result.stdout.utf8)
                    )
                    lastKnownToday = document.date
                    if selectedDate == requestedDate {
                        selectedDate = document.date
                        watcher.watch(directory: dayDirectory)
                    }
                }
                refreshAvailableDates()
                if selectedDate == requestedDate || (requestingToday && isViewingToday) {
                    reloadFromDisk()
                }
            } catch {
                if selectedDate == requestedDate {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func captureWork(
        title: String,
        idempotencyKey: String,
        onSuccess: @escaping () -> Void
    ) {
        runWorkMutation(
            .todoAdd(title: title, idempotencyKey: idempotencyKey),
            successNotice: "已记录",
            onSuccess: onSuccess
        )
    }

    func setWorkStatus(
        itemID: String,
        status: WorkStatus,
        version: Int,
        onSuccess: (() -> Void)? = nil
    ) {
        let notice: String = switch status {
        case .cancelled: "已取消"
        case .completed: "已完成"
        default: "状态已更新"
        }
        runWorkMutation(
            .todoStatus(id: itemID, status: status, expectedVersion: version),
            successNotice: notice,
            onSuccess: onSuccess
        )
    }

    func editWork(
        itemID: String,
        title: String,
        detail: String,
        version: Int,
        idempotencyKey: String,
        onSuccess: @escaping () -> Void
    ) {
        runWorkMutation(
            .todoEdit(
                id: itemID,
                title: title,
                detail: detail,
                expectedVersion: version,
                idempotencyKey: idempotencyKey
            ),
            successNotice: "任务已更新",
            onSuccess: onSuccess
        )
    }

    func appendProgress(
        itemID: String,
        text: String,
        version: Int,
        idempotencyKey: String,
        onSuccess: @escaping () -> Void
    ) {
        runWorkMutation(
            .todoNote(
                id: itemID,
                text: text,
                expectedVersion: version,
                idempotencyKey: idempotencyKey
            ),
            successNotice: "进展已追加",
            onSuccess: onSuccess
        )
    }

    func deleteWork(itemID: String, version: Int, onSuccess: (() -> Void)? = nil) {
        runWorkMutation(
            .todoDelete(
                id: itemID,
                expectedVersion: version,
                idempotencyKey: "ui:delete:\(itemID):\(version)"
            ),
            successNotice: "已删除",
            onSuccess: onSuccess
        )
    }

    func undo(eventID: String) {
        let expectedVersion: Int
        if let latest = work?.latestReversible, latest.event.eventId == eventID {
            expectedVersion = latest.expectedVersion
        } else if let item = work?.allItems.first(where: {
            $0.events.contains { $0.eventId == eventID }
        }) {
            expectedVersion = item.version
        } else {
            errorMessage = "找不到要撤销的变更"
            return
        }
        runWorkMutation(
            .todoUndo(eventID: eventID, expectedVersion: expectedVersion),
            successNotice: "已撤销"
        )
    }

    func analyzeClaudeSession(tail: String) {
        let value = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSessionLocating, !isSessionAnalyzing, !isSessionApplying else { return }
        isSessionAnalyzing = true
        errorMessage = nil
        notice = "Agent 正在定位并通读 Claude session…"
        sessionTask = Task {
            defer { isSessionAnalyzing = false }
            do {
                let result = try await runner.run(.assistantAnalyze(tail: value))
                sessionAnalysis = try decoder.decode(
                    SessionAnalysis.self,
                    from: Data(result.stdout.utf8)
                )
                locatedSession = nil
                setTransientNotice("Session 已分析")
            } catch is CancellationError {
                setTransientNotice("已取消")
            } catch {
                errorMessage = error.localizedDescription
                notice = nil
            }
        }
    }

    /// Fast locate-only phase: find the matching session without running the agent.
    func locateSession(tail: String) {
        let value = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isSessionLocating, !isSessionAnalyzing, !isSessionApplying else { return }
        isSessionLocating = true
        errorMessage = nil
        notice = "正在定位 Claude session…"
        sessionTask = Task {
            defer { isSessionLocating = false }
            do {
                let result = try await runner.run(.assistantLocate(tail: value))
                locatedSession = try decoder.decode(
                    ClaudeSessionMatch.self,
                    from: Data(result.stdout.utf8)
                )
                notice = nil
            } catch is CancellationError {
                setTransientNotice("已取消")
            } catch {
                errorMessage = error.localizedDescription
                notice = nil
            }
        }
    }

    /// Load recent parent sessions for the pick-without-paste list.
    ///
    /// Fast path returns cached agent summaries when present. Missing summaries are
    /// filled once via ``assistant summarize`` (fingerprint cache; no repeat agent calls).
    func loadRecentSessions(limit: Int = 15) {
        Task {
            do {
                let result = try await runner.run(.assistantSessions(limit: limit))
                recentSessions = try decoder.decode(
                    RecentSessionList.self,
                    from: Data(result.stdout.utf8)
                ).sessions
                ensureRecentSessionSummaries(limit: limit)
            } catch is CancellationError {
                // ignore
            } catch {
                // A failed listing is non-fatal; leave the composer usable.
            }
        }
    }

    /// Persist agent summaries for listed sessions that lack a fingerprint cache hit.
    private func ensureRecentSessionSummaries(limit: Int) {
        let needsWork = recentSessions.contains { session in
            session.summaryStatus == "pending" || session.summaryStatus == nil
        }
        guard needsWork, !isSessionSummarizing else { return }
        isSessionSummarizing = true
        summaryTask?.cancel()
        summaryTask = Task {
            defer { isSessionSummarizing = false }
            do {
                let result = try await runner.run(.assistantSummarize(limit: limit))
                let payload = try decoder.decode(
                    RecentSessionSummarizeResult.self,
                    from: Data(result.stdout.utf8)
                )
                recentSessions = payload.sessions
            } catch is CancellationError {
                // ignore
            } catch {
                // Non-fatal: keep preview/pending rows; next open retries only uncached sessions.
            }
        }
    }

    /// Analyze one already-chosen session file, skipping the locate phase.
    func analyzeConfirmedSession(sourceFile: String) {
        guard !isSessionLocating, !isSessionAnalyzing, !isSessionApplying else { return }
        // Prefer the interactive full analysis over background list summarization.
        summaryTask?.cancel()
        isSessionSummarizing = false
        isSessionAnalyzing = true
        errorMessage = nil
        notice = "Agent 正在通读该 Claude session…"
        sessionTask = Task {
            defer { isSessionAnalyzing = false }
            do {
                let result = try await runner.run(.assistantAnalyzeFile(sessionFile: sourceFile))
                sessionAnalysis = try decoder.decode(
                    SessionAnalysis.self,
                    from: Data(result.stdout.utf8)
                )
                locatedSession = nil
                setTransientNotice("Session 已分析")
            } catch is CancellationError {
                setTransientNotice("已取消")
            } catch {
                errorMessage = error.localizedDescription
                notice = nil
            }
        }
    }

    /// Cancel an in-flight locate, analyze, or background session summarize.
    func cancelSession() {
        sessionTask?.cancel()
        summaryTask?.cancel()
    }

    func applySessionAnalysis(onSuccess: @escaping () -> Void) {
        guard let analysis = sessionAnalysis,
              !isSessionAnalyzing,
              !isSessionApplying else {
            return
        }
        isSessionApplying = true
        errorMessage = nil
        notice = "正在写入确认的 Todo 更新…"
        Task {
            defer { isSessionApplying = false }
            do {
                let result = try await runner.run(
                    .assistantApply(analysisID: analysis.analysisId)
                )
                _ = try decoder.decode(
                    SessionApplyResult.self,
                    from: Data(result.stdout.utf8)
                )
                sessionAnalysis = nil
                refreshAvailableDates()
                if isViewingToday {
                    reloadFromDisk()
                    refreshWorkProjection()
                } else {
                    select(date: lastKnownToday)
                }
                setTransientNotice("Todo 已更新")
                onSuccess()
            } catch {
                errorMessage = error.localizedDescription
                notice = nil
                refreshWorkProjection()
            }
        }
    }

    func clearSessionAnalysis() {
        guard !isSessionLocating, !isSessionAnalyzing, !isSessionApplying else { return }
        sessionAnalysis = nil
        locatedSession = nil
        errorMessage = nil
    }

    private func runWorkMutation(
        _ command: BriefctlCommand,
        successNotice: String,
        onSuccess: (() -> Void)? = nil
    ) {
        guard isViewingToday, !isWorkMutating else { return }
        isWorkMutating = true
        errorMessage = nil
        Task {
            defer { isWorkMutating = false }
            do {
                _ = try await runner.run(command)
                reloadFromDisk()
                refreshAvailableDates()
                setTransientNotice(successNotice)
                onSuccess?()
            } catch {
                errorMessage = error.localizedDescription
                refreshWorkProjection()
            }
        }
    }

    func openFolder() {
        let directory = dayDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func computeStaleness(for brief: BriefDocument?) -> Bool {
        guard let generated = brief?.generatedAtDate else { return brief == nil }
        let threshold = brief?.stalenessHours ?? 36
        let hours = Date().timeIntervalSince(generated) / 3600
        return hours > threshold
    }
}
