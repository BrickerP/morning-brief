import SwiftUI

struct AgentChatView: View {
    @EnvironmentObject private var store: BriefStore

    @State private var draft = ""
    @State private var showingApplyConfirmation = false
    @State private var expandedSessionID: String?
    @State private var sessionSourceTab: SessionSourceTab = .claude
    @AppStorage("MorningBrief.selectedLens") private var selectedLensRaw = "agent"
    @FocusState private var composerFocused: Bool

    private enum SessionSourceTab: String, CaseIterable, Identifiable {
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if let analysis = store.sessionAnalysis {
                        pastedEnding
                        analysisView(analysis)
                    } else if let located = store.locatedSession {
                        locatedView(located)
                    } else {
                        recentSessionsList
                        composer
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.sm)
                .textSelection(.enabled)
            }

            Divider()
            actions
        }
        .confirmationDialog(
            "确认写入 \(store.sessionAnalysis?.proposals.count ?? 0) 条 Todo 更新？",
            isPresented: $showingApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认更新") {
                store.applySessionAnalysis {
                    draft = ""
                    selectedLensRaw = "work"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("系统会重新检查 Todo 版本；如果你分析后手工改过任务，将拒绝写入并要求重新分析。")
        }
    }

    private var sessionsForTab: [RecentSession] {
        store.recentSessions.filter { $0.source == sessionSourceTab.rawValue }
    }

    @ViewBuilder
    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                Text("最近会话")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if store.isSessionSummarizing {
                    ProgressView()
                        .controlSize(.mini)
                    if let progress = store.sessionSummaryProgress {
                        Text("生成摘要 \(progress.completed)/\(progress.total)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    } else {
                        Text("生成摘要")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Picker("来源", selection: $sessionSourceTab) {
                ForEach(SessionSourceTab.allCases) { tab in
                    Text("\(tab.title) \(store.recentSessions.filter { $0.source == tab.rawValue }.count)")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: sessionSourceTab) {
                expandedSessionID = nil
            }

            if sessionsForTab.isEmpty {
                Text(store.recentSessions.isEmpty ? "暂无会话" : "该来源暂无最近会话")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, DS.Space.xs)
            } else {
                ForEach(sessionsForTab) { session in
                    recentSessionRow(session)
                }
            }
        }
    }

    private func recentSessionRow(_ session: RecentSession) -> some View {
        let expanded = expandedSessionID == session.id
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedSessionID = expanded ? nil : session.id
                }
            } label: {
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Image(systemName: session.summaryStatus == "ready" ? "text.quote" : "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayTitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(session.summaryStatus == "pending" ? .secondary : .primary)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                        if sessionShowsAskCue(session) {
                            Text(session.preview)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                        }
                        HStack(spacing: 6) {
                            Text(sessionProject(session.project))
                                .lineLimit(1)
                            if session.subagentCount > 0 {
                                Text("· \(session.subagentCount) subagent")
                            }
                            if let date = session.modifiedAtDate {
                                Text("· \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: DS.Space.xs)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                sessionExpandBody(session)
            }
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    /// Latest user-ask cue under a ready summary (helps skim when blurbs rhyme).
    private func sessionShowsAskCue(_ session: RecentSession) -> Bool {
        guard session.summaryStatus == "ready",
              let summary = session.summary, !summary.isEmpty,
              !session.preview.isEmpty
        else { return false }
        return session.preview != summary
            && !summary.contains(session.preview.prefix(min(16, session.preview.count)))
    }

    @ViewBuilder
    private func sessionExpandBody(_ session: RecentSession) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let detail = session.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if session.summaryStatus == "pending" || session.summaryStatus == nil {
                Text("正在生成完整摘要…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if session.summaryStatus == "failed" {
                Text("完整摘要生成失败，可先看下方用户原话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !session.recentAsks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近用户原话")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(session.recentAsks.enumerated()), id: \.offset) { _, ask in
                        Text(ask)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            if session.supportsAnalyze {
                Button {
                    store.analyzeConfirmedSession(sourceFile: session.sourceFile)
                } label: {
                    Text("通读分析")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isSessionAnalyzing || store.isSessionLocating)
            } else {
                Text("\(session.sourceTitle) 会话目前只支持摘要预览")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Turn a Claude/Cursor project dir name into a readable repo/folder cue.
    private func sessionProject(_ raw: String) -> String {
        // Codex (and similar) use day folders — keep as-is.
        if raw.count == 10,
           raw[raw.index(raw.startIndex, offsetBy: 4)] == "-",
           raw[raw.index(raw.startIndex, offsetBy: 7)] == "-" {
            return raw
        }
        let skip: Set<String> = [
            "Users", "home", "Downloads", "Desktop", "Documents", "Library",
            "projects", "repos", "code", "src", "dev", "tmp",
        ]
        let parts = raw.split(whereSeparator: { $0 == "-" || $0 == "/" })
            .map(String.init)
            .filter { !$0.isEmpty }
        let meaningful = parts.filter { !skip.contains($0) && !$0.hasPrefix(".") }
        let use = meaningful.isEmpty ? parts : meaningful
        guard !use.isEmpty else { return raw }
        if use.count >= 2, use.suffix(2).allSatisfy({ $0.count <= 16 }) {
            return use.suffix(2).joined(separator: "-")
        }
        return use.last ?? raw
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    @ViewBuilder
    private func locatedView(_ located: ClaudeSessionMatch) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if !draft.isEmpty { pastedEnding }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("已定位会话")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(
                        located.confidence == "high" ? "精确匹配" : "内容匹配",
                        systemImage: "scope"
                    )
                    .font(.caption2)
                    .foregroundStyle(located.confidence == "high" ? .green : .orange)
                }
                Text("\(sessionProject(located.project)) · \(located.subagentCount) 个 subagent")
                    .font(.callout)
                Text("Session \(located.id)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if !located.matchedAnchors.isEmpty {
                    Text("命中：\(located.matchedAnchors.prefix(2).joined(separator: " / "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(DS.Palette.cardStroke)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }

    private var composer: some View {
        TextEditor(text: $draft)
            .font(.callout)
            .scrollContentBackground(.hidden)
            .padding(6)
            .focused($composerFocused)
            .accessibilityLabel("会话结尾")
            .frame(minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Palette.cardStroke)
            }
            .onAppear { composerFocused = true }
    }

    @ViewBuilder
    private var pastedEnding: some View {
        if !draft.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("你")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(draft)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(DS.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
        }
    }

    private func analysisView(_ analysis: SessionAnalysis) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("Agent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(
                        analysis.session.confidence == "high" ? "精确匹配" : "内容匹配",
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.green)
                }
                Text(analysis.summary)
                    .font(.callout)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Session \(analysis.session.id) · 主会话 + \(analysis.session.subagentCount) 个 subagent"
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if !analysis.todoMatches.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    sectionTitle("匹配的 Todo", count: analysis.todoMatches.count)
                    ForEach(analysis.todoMatches) { match in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(match.title)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text("\(Int((match.confidence * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(match.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(DS.Space.sm)
                        .background(DS.Palette.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                sectionTitle("建议更新", count: analysis.proposals.count)
                if analysis.proposals.isEmpty {
                    Text("没有需要写入的 Todo 更新。Summary 仍可直接复制。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analysis.proposals) { proposal in
                        proposalRow(proposal)
                    }
                }
            }

        }
    }

    private func proposalRow(_ proposal: SessionTodoProposal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(proposal.action.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                if let itemTitle = proposal.itemTitle {
                    Text("· \(itemTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(proposal.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(proposal.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.cardFill)
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .stroke(DS.Palette.cardStroke)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            if store.sessionAnalysis != nil || store.locatedSession != nil {
                Button("重新开始") {
                    store.clearSessionAnalysis()
                    draft = ""
                    composerFocused = true
                }
                .buttonStyle(.borderless)
                .disabled(store.isSessionLocating || store.isSessionAnalyzing || store.isSessionApplying)
            }

            Spacer()

            if store.isSessionLocating {
                ProgressView().controlSize(.small)
                Text("定位中…").font(.caption).foregroundStyle(.secondary)
                Button("取消") { store.cancelSession() }
                    .buttonStyle(.borderless)
            } else if store.isSessionAnalyzing {
                ProgressView().controlSize(.small)
                Text("通读中…").font(.caption).foregroundStyle(.secondary)
                Button("取消") { store.cancelSession() }
                    .buttonStyle(.borderless)
            } else if store.isSessionApplying {
                ProgressView().controlSize(.small)
                Text("写入中…").font(.caption).foregroundStyle(.secondary)
            } else if let analysis = store.sessionAnalysis, !analysis.proposals.isEmpty {
                Button("确认 \(analysis.proposals.count) 条更新") {
                    showingApplyConfirmation = true
                }
                .buttonStyle(.borderedProminent)
            } else if let located = store.locatedSession {
                Button("确认并分析") {
                    store.analyzeConfirmedSession(sourceFile: located.sourceFile)
                }
                .buttonStyle(.borderedProminent)
            } else if store.sessionAnalysis == nil {
                Button("定位并分析") {
                    store.locateSession(tail: draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
