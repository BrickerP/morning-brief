import Foundation

enum AgentSessionSource: String, CaseIterable, Identifiable, Hashable {
    case claude
    case codex
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    var storageKey: String { "MorningBrief.agentLimit.\(rawValue)" }

    var defaultLimit: Int {
        switch self {
        case .claude: 10
        case .codex: 5
        case .cursor: 5
        }
    }
}

struct AgentSessionLimits: Equatable {
    var claude: Int
    var codex: Int
    var cursor: Int

    static let minCount = 1
    static let maxCount = 40

    static func load() -> AgentSessionLimits {
        func read(_ source: AgentSessionSource) -> Int {
            let stored = UserDefaults.standard.object(forKey: source.storageKey) as? Int
            return clamp(stored ?? source.defaultLimit)
        }
        return AgentSessionLimits(
            claude: read(.claude),
            codex: read(.codex),
            cursor: read(.cursor)
        )
    }

    static func clamp(_ value: Int) -> Int {
        min(maxCount, max(minCount, value))
    }

    subscript(source: AgentSessionSource) -> Int {
        get {
            switch source {
            case .claude: claude
            case .codex: codex
            case .cursor: cursor
            }
        }
        set {
            let value = Self.clamp(newValue)
            switch source {
            case .claude: claude = value
            case .codex: codex = value
            case .cursor: cursor = value
            }
        }
    }

    func persist() {
        UserDefaults.standard.set(claude, forKey: AgentSessionSource.claude.storageKey)
        UserDefaults.standard.set(codex, forKey: AgentSessionSource.codex.storageKey)
        UserDefaults.standard.set(cursor, forKey: AgentSessionSource.cursor.storageKey)
    }
}

enum AgentFeature {
    static let sessionEffectID = "agent.session"
    static let summarizeEffectID = "agent.summarize"

    struct State {
        var limits = AgentSessionLimits.load()
        var selectedSource: AgentSessionSource = .claude
        var recentSessions: [RecentSession] = []
        var sessionAnalysis: SessionAnalysis?
        var locatedSession: ClaudeSessionMatch?

        var isSessionLocating = false
        var isSessionAnalyzing = false
        var isSessionApplying = false
        var isSessionSummarizing = false
        var isSessionListing = false
        var sessionSummaryProgress: (completed: Int, total: Int)?

        var notice: String?
        var errorMessage: String?

        /// Coalesce list fetches when the Agent lens re-appears quickly.
        var lastSessionListAt: Date?
        var lastSummaryEnsureAt: Date?

        /// Pending source files for progressive summarize (one at a time).
        var pendingSummaryFiles: [String] = []

        func sessions(for source: AgentSessionSource) -> [RecentSession] {
            recentSessions.filter { $0.source == source.rawValue }
        }
    }

    enum Action {
        case onAppear
        case loadRecentSessions
        case reloadSessions
        case selectSource(AgentSessionSource)
        case setLimit(source: AgentSessionSource, count: Int)
        case analyzeConfirmedSession(sourceFile: String)
        case locateSession(tail: String)
        case analyzeClaudeSession(tail: String)
        case applySessionAnalysis
        case clearSessionAnalysis
        case cancelInFlight
        case clearNotice

        // Internal
        case sessionsLoaded([RecentSession])
        case ensureSummaries
        case summarizeNext
        case sessionsReloaded([RecentSession])
        case summaryProgress(completed: Int, total: Int)
        case summarizingFinished
        case located(ClaudeSessionMatch)
        case analyzed(SessionAnalysis)
        case applySucceeded
        case cancelled
        case failed(String)
    }

    static func reduce(
        into state: inout State,
        action: Action,
        client: BriefctlClient
    ) -> Effect<Action> {
        switch action {
        case .onAppear, .loadRecentSessions:
            if let last = state.lastSessionListAt,
               Date().timeIntervalSince(last) < 2,
               !state.recentSessions.isEmpty {
                return .run { [.ensureSummaries] }
            }
            return fetchSessions(state: &state, client: client)

        case .reloadSessions:
            state.lastSessionListAt = nil
            state.lastSummaryEnsureAt = nil
            return .sequence(
                .cancel(id: summarizeEffectID),
                fetchSessions(state: &state, client: client, cancelSummarizeFlags: true)
            )

        case let .selectSource(source):
            state.selectedSource = source
            return .none

        case let .setLimit(source, count):
            let clamped = AgentSessionLimits.clamp(count)
            guard state.limits[source] != clamped else { return .none }
            state.limits[source] = clamped
            state.limits.persist()
            state.selectedSource = source
            state.lastSessionListAt = nil
            state.lastSummaryEnsureAt = nil
            state.notice = "正在刷新 \(source.title) 最近 \(clamped) 个会话…"
            return .sequence(
                .cancel(id: summarizeEffectID),
                fetchSessions(state: &state, client: client, cancelSummarizeFlags: true)
            )

        case let .sessionsLoaded(sessions):
            state.isSessionListing = false
            state.recentSessions = sessions
            if state.notice?.hasPrefix("正在刷新") == true
                || state.notice?.hasPrefix("正在加载") == true {
                state.notice = nil
            }
            return .run { [.ensureSummaries] }

        case .ensureSummaries:
            let pending = state.recentSessions.compactMap { session -> String? in
                guard session.summaryStatus == "pending" || session.summaryStatus == nil else {
                    return nil
                }
                return session.sourceFile
            }
            guard !pending.isEmpty, !state.isSessionSummarizing else { return .none }
            if let last = state.lastSummaryEnsureAt, Date().timeIntervalSince(last) < 8 {
                return .none
            }
            state.lastSummaryEnsureAt = Date()
            state.isSessionSummarizing = true
            state.pendingSummaryFiles = pending
            state.sessionSummaryProgress = (completed: 0, total: pending.count)
            return .run(id: summarizeEffectID) { [.summarizeNext] }

        case .summarizeNext:
            guard state.isSessionSummarizing, !state.pendingSummaryFiles.isEmpty else {
                state.isSessionSummarizing = false
                state.sessionSummaryProgress = nil
                state.pendingSummaryFiles = []
                return .none
            }
            let sourceFile = state.pendingSummaryFiles.removeFirst()
            let completedBefore = state.sessionSummaryProgress?.completed ?? 0
            let total = state.sessionSummaryProgress?.total ?? 1
            let limits = state.limits
            return .run(id: summarizeEffectID) {
                do {
                    try Task.checkCancellation()
                    do {
                        _ = try await client.run(.assistantSummarizeFile(sessionFile: sourceFile))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Keep going so one failure does not block the rest.
                    }
                    let listed = try await client.assistantSessions(
                        claudeLimit: limits.claude,
                        codexLimit: limits.codex,
                        cursorLimit: limits.cursor
                    )
                    return [
                        .summaryProgress(completed: completedBefore + 1, total: total),
                        .sessionsReloaded(listed),
                        .summarizeNext,
                    ]
                } catch is CancellationError {
                    return [.cancelled]
                } catch {
                    return [.summarizingFinished]
                }
            }

        case let .sessionsReloaded(sessions):
            state.recentSessions = sessions
            return .none

        case let .summaryProgress(completed, total):
            state.sessionSummaryProgress = (completed: completed, total: total)
            return .none

        case .summarizingFinished:
            state.isSessionSummarizing = false
            state.sessionSummaryProgress = nil
            state.pendingSummaryFiles = []
            state.lastSummaryEnsureAt = nil
            return .none

        case let .analyzeConfirmedSession(sourceFile):
            guard !state.isSessionLocating, !state.isSessionAnalyzing, !state.isSessionApplying else {
                return .none
            }
            state.isSessionSummarizing = false
            state.sessionSummaryProgress = nil
            state.pendingSummaryFiles = []
            state.isSessionAnalyzing = true
            state.errorMessage = nil
            state.notice = "Agent 正在通读该 Claude session…"
            return .run(id: sessionEffectID) {
                do {
                    let analysis = try await client.assistantAnalyzeFile(sessionFile: sourceFile)
                    return [.analyzed(analysis)]
                } catch is CancellationError {
                    return [.cancelled]
                } catch {
                    return [.failed(error.localizedDescription)]
                }
            }

        case let .locateSession(tail):
            let value = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !state.isSessionLocating,
                  !state.isSessionAnalyzing,
                  !state.isSessionApplying else { return .none }
            state.isSessionLocating = true
            state.errorMessage = nil
            state.notice = "正在定位 Claude session…"
            return .run(id: sessionEffectID) {
                do {
                    let match = try await client.assistantLocate(tail: value)
                    return [.located(match)]
                } catch is CancellationError {
                    return [.cancelled]
                } catch {
                    return [.failed(error.localizedDescription)]
                }
            }

        case let .analyzeClaudeSession(tail):
            let value = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !state.isSessionLocating,
                  !state.isSessionAnalyzing,
                  !state.isSessionApplying else { return .none }
            state.isSessionAnalyzing = true
            state.errorMessage = nil
            state.notice = "Agent 正在定位并通读 Claude session…"
            return .run(id: sessionEffectID) {
                do {
                    let analysis = try await client.assistantAnalyze(tail: value)
                    return [.analyzed(analysis)]
                } catch is CancellationError {
                    return [.cancelled]
                } catch {
                    return [.failed(error.localizedDescription)]
                }
            }

        case let .located(match):
            state.isSessionLocating = false
            state.locatedSession = match
            state.notice = nil
            return .none

        case let .analyzed(analysis):
            state.isSessionAnalyzing = false
            state.isSessionLocating = false
            state.sessionAnalysis = analysis
            state.locatedSession = nil
            state.notice = "Session 已分析"
            return .none

        case .applySessionAnalysis:
            guard let analysis = state.sessionAnalysis,
                  !state.isSessionAnalyzing,
                  !state.isSessionApplying else { return .none }
            state.isSessionApplying = true
            state.errorMessage = nil
            state.notice = "正在写入确认的 Todo 更新…"
            let analysisID = analysis.analysisId
            return .run(id: sessionEffectID) {
                do {
                    _ = try await client.assistantApply(analysisID: analysisID)
                    return [.applySucceeded]
                } catch {
                    return [.failed(error.localizedDescription)]
                }
            }

        case .applySucceeded:
            state.isSessionApplying = false
            state.sessionAnalysis = nil
            state.notice = nil
            return .none

        case .clearSessionAnalysis:
            guard !state.isSessionLocating,
                  !state.isSessionAnalyzing,
                  !state.isSessionApplying else { return .none }
            state.sessionAnalysis = nil
            state.locatedSession = nil
            state.errorMessage = nil
            return .none

        case .cancelInFlight:
            state.isSessionLocating = false
            state.isSessionAnalyzing = false
            state.isSessionSummarizing = false
            state.isSessionListing = false
            state.sessionSummaryProgress = nil
            state.pendingSummaryFiles = []
            state.lastSummaryEnsureAt = nil
            state.notice = "已取消"
            return .sequence(
                .cancel(id: summarizeEffectID),
                .cancel(id: sessionEffectID)
            )

        case .cancelled:
            state.isSessionLocating = false
            state.isSessionAnalyzing = false
            state.isSessionSummarizing = false
            state.isSessionListing = false
            state.sessionSummaryProgress = nil
            state.pendingSummaryFiles = []
            state.lastSummaryEnsureAt = nil
            state.notice = "已取消"
            return .none

        case let .failed(message):
            state.isSessionLocating = false
            state.isSessionAnalyzing = false
            state.isSessionApplying = false
            state.isSessionListing = false
            state.errorMessage = message
            state.notice = nil
            return .none

        case .clearNotice:
            state.notice = nil
            return .none
        }
    }

    private static func fetchSessions(
        state: inout State,
        client: BriefctlClient,
        cancelSummarizeFlags: Bool = false
    ) -> Effect<Action> {
        if cancelSummarizeFlags {
            state.isSessionSummarizing = false
            state.sessionSummaryProgress = nil
            state.pendingSummaryFiles = []
        }
        state.lastSessionListAt = Date()
        state.isSessionListing = true
        state.errorMessage = nil
        let limits = state.limits
        return .run(id: sessionEffectID) {
            do {
                let sessions = try await client.assistantSessions(
                    claudeLimit: limits.claude,
                    codexLimit: limits.codex,
                    cursorLimit: limits.cursor
                )
                return [.sessionsLoaded(sessions)]
            } catch is CancellationError {
                return []
            } catch {
                return []
            }
        }
    }
}

extension BriefctlClient {
    private static let decoder = JSONDecoder()

    func assistantSessions(
        claudeLimit: Int,
        codexLimit: Int,
        cursorLimit: Int
    ) async throws -> [RecentSession] {
        let result = try await run(
            .assistantSessions(
                claudeLimit: claudeLimit,
                codexLimit: codexLimit,
                cursorLimit: cursorLimit
            )
        )
        return try Self.decoder.decode(RecentSessionList.self, from: Data(result.stdout.utf8)).sessions
    }

    func assistantAnalyzeFile(sessionFile: String) async throws -> SessionAnalysis {
        let result = try await run(.assistantAnalyzeFile(sessionFile: sessionFile))
        return try Self.decoder.decode(SessionAnalysis.self, from: Data(result.stdout.utf8))
    }

    func assistantAnalyze(tail: String) async throws -> SessionAnalysis {
        let result = try await run(.assistantAnalyze(tail: tail))
        return try Self.decoder.decode(SessionAnalysis.self, from: Data(result.stdout.utf8))
    }

    func assistantLocate(tail: String) async throws -> ClaudeSessionMatch {
        let result = try await run(.assistantLocate(tail: tail))
        return try Self.decoder.decode(ClaudeSessionMatch.self, from: Data(result.stdout.utf8))
    }

    func assistantApply(analysisID: String) async throws -> SessionApplyResult {
        let result = try await run(.assistantApply(analysisID: analysisID))
        return try Self.decoder.decode(SessionApplyResult.self, from: Data(result.stdout.utf8))
    }
}
