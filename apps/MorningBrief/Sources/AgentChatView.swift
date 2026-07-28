import SwiftUI

struct AgentChatView: View {
    @ObservedObject var appStore: Store<AppFeature.State, AppFeature.Action>

    @State private var draft = ""
    @State private var showingApplyConfirmation = false
    @State private var expandedSessionID: String?
    @State private var limitDrafts: [AgentSessionSource: String] = [:]
    @FocusState private var composerFocused: Bool
    @FocusState private var focusedLimitSource: AgentSessionSource?

    private var agent: AgentFeature.State { appStore.state.agent }
    private var selectedSource: AgentSessionSource { agent.selectedSource }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if let analysis = agent.sessionAnalysis {
                        pastedEnding
                        analysisView(analysis)
                    } else if let located = agent.locatedSession {
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
            // Inline confirm — system confirmationDialog can interrupt focus.
            if showingApplyConfirmation {
                applyConfirmBanner
            }
            actions
        }
        .onAppear {
            appStore.send(.agent(.onAppear))
        }
    }

    private var applyConfirmBanner: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("确认写入 \(agent.sessionAnalysis?.proposals.count ?? 0) 条 Todo 更新？")
                .font(.caption.weight(.semibold))
            Text("系统会重新检查版本；若分析后手工改过任务，将拒绝写入并要求重新分析。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: DS.Space.sm) {
                Button("取消") {
                    showingApplyConfirmation = false
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button("确认更新") {
                    showingApplyConfirmation = false
                    draft = ""
                    appStore.send(.agent(.applySessionAnalysis))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(agent.isSessionApplying)
            }
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var sessionsForTab: [RecentSession] {
        agent.sessions(for: selectedSource)
    }

    @ViewBuilder
    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xs) {
                Text("最近会话")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if agent.isSessionListing {
                    ProgressView()
                        .controlSize(.mini)
                    Text("加载中")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if agent.isSessionSummarizing {
                    ProgressView()
                        .controlSize(.mini)
                    if let progress = agent.sessionSummaryProgress {
                        Text("生成摘要 \(progress.completed)/\(progress.total)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    } else {
                        Text("生成摘要")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Button {
                        appStore.send(.agent(.reloadSessions))
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(agent.isSessionAnalyzing || agent.isSessionLocating)
                }
            }

            sourceLimitPicker

            if sessionsForTab.isEmpty {
                Text(agent.recentSessions.isEmpty ? "暂无会话" : "该来源暂无最近会话")
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

    /// Three source cards — each always shows − / number field / + for its session limit.
    private var sourceLimitPicker: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(AgentSessionSource.allCases) { source in
                sourceLimitCard(source)
            }
        }
        .onAppear { syncLimitDrafts(from: agent.limits) }
        .onChange(of: agent.limits) { _, limits in
            // Don't clobber the field the user is typing into.
            for source in AgentSessionSource.allCases where focusedLimitSource != source {
                limitDrafts[source] = "\(limits[source])"
            }
        }
    }

    private func sourceLimitCard(_ source: AgentSessionSource) -> some View {
        let selected = selectedSource == source
        let loaded = agent.sessions(for: source).count
        let limit = agent.limits[source]
        let draft = Binding(
            get: { limitDrafts[source] ?? "\(limit)" },
            set: { limitDrafts[source] = $0 }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    appStore.send(.agent(.selectSource(source)))
                    expandedSessionID = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Text(source.title)
                        .font(.caption.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    Spacer(minLength: 0)
                    Text("会话数")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    appStore.send(.agent(.selectSource(source)))
                    nudgeLimit(source, -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(limit <= AgentSessionLimits.minCount
                    || agent.isSessionListing
                    || agent.isSessionAnalyzing)

                TextField("8", text: draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 48, maxWidth: .infinity)
                    .focused($focusedLimitSource, equals: source)
                    .onSubmit { commitLimitDraft(source) }
                    .onChange(of: focusedLimitSource) { old, new in
                        if old == source, new != source {
                            commitLimitDraft(source)
                        }
                        if new == source {
                            appStore.send(.agent(.selectSource(source)))
                        }
                    }
                    .disabled(agent.isSessionListing || agent.isSessionAnalyzing)
                    .accessibilityLabel("\(source.title) 最近会话数量")

                Button {
                    appStore.send(.agent(.selectSource(source)))
                    nudgeLimit(source, 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(limit >= AgentSessionLimits.maxCount
                    || agent.isSessionListing
                    || agent.isSessionAnalyzing)
            }

            HStack(spacing: 6) {
                Text("最近 \(AgentSessionLimits.clamp(Int(draft.wrappedValue) ?? limit)) 个")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if loaded != limit {
                    Text("· 已载 \(loaded)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Button("应用") {
                    appStore.send(.agent(.selectSource(source)))
                    commitLimitDraft(source)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(agent.isSessionListing || agent.isSessionAnalyzing)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(selected ? AppChrome.accent.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(
                    selected ? AppChrome.accent.opacity(0.5) : Color.primary.opacity(0.08),
                    lineWidth: selected ? 1.5 : 1
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appStore.send(.agent(.selectSource(source)))
        }
    }

    private func syncLimitDrafts(from limits: AgentSessionLimits) {
        for source in AgentSessionSource.allCases {
            limitDrafts[source] = "\(limits[source])"
        }
    }

    private func nudgeLimit(_ source: AgentSessionSource, _ delta: Int) {
        let next = agent.limits[source] + delta
        appStore.send(.agent(.setLimit(source: source, count: next)))
        limitDrafts[source] = "\(AgentSessionLimits.clamp(next))"
        focusedLimitSource = nil
    }

    private func commitLimitDraft(_ source: AgentSessionSource) {
        let raw = (limitDrafts[source] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Int(raw) ?? agent.limits[source]
        focusedLimitSource = nil
        appStore.send(.agent(.setLimit(source: source, count: parsed)))
        limitDrafts[source] = "\(AgentSessionLimits.clamp(parsed))"
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
                    appStore.send(.agent(.analyzeConfirmedSession(sourceFile: session.sourceFile)))
                } label: {
                    Text("通读分析")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(agent.isSessionAnalyzing || agent.isSessionLocating)
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
            if agent.sessionAnalysis != nil || agent.locatedSession != nil {
                Button("重新开始") {
                    appStore.send(.agent(.clearSessionAnalysis))
                    draft = ""
                    composerFocused = true
                }
                .buttonStyle(.borderless)
                .disabled(agent.isSessionLocating || agent.isSessionAnalyzing || agent.isSessionApplying)
            }

            Spacer()

            if agent.isSessionLocating {
                ProgressView().controlSize(.small)
                Text("定位中…").font(.caption).foregroundStyle(.secondary)
                Button("取消") { appStore.send(.agent(.cancelInFlight)) }
                    .buttonStyle(.borderless)
            } else if agent.isSessionAnalyzing {
                ProgressView().controlSize(.small)
                Text("通读中…").font(.caption).foregroundStyle(.secondary)
                Button("取消") { appStore.send(.agent(.cancelInFlight)) }
                    .buttonStyle(.borderless)
            } else if agent.isSessionApplying {
                ProgressView().controlSize(.small)
                Text("写入中…").font(.caption).foregroundStyle(.secondary)
            } else if let analysis = agent.sessionAnalysis, !analysis.proposals.isEmpty {
                Button("确认 \(analysis.proposals.count) 条更新") {
                    showingApplyConfirmation = true
                }
                .buttonStyle(.borderedProminent)
            } else if let located = agent.locatedSession {
                Button("确认并分析") {
                    appStore.send(.agent(.analyzeConfirmedSession(sourceFile: located.sourceFile)))
                }
                .buttonStyle(.borderedProminent)
            } else if agent.sessionAnalysis == nil {
                Button("定位并分析") {
                    appStore.send(.agent(.locateSession(tail: draft)))
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
