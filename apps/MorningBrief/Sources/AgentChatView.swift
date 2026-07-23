import SwiftUI

struct AgentChatView: View {
    @EnvironmentObject private var store: BriefStore

    @State private var draft = ""
    @State private var showingApplyConfirmation = false
    @AppStorage("MorningBrief.selectedLens") private var selectedLensRaw = "agent"
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    intro
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Label("Claude Session → Todo", systemImage: "bubble.left.and.text.bubble.right")
                .font(.headline)
            Text("从下方最近会话里直接选一条，或粘贴 terminal 中 Claude session 的结尾。Agent 会通读主会话和子 Agent，再匹配今天的 Todo。分析阶段不会修改台账。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var recentSessionsList: some View {
        if !store.recentSessions.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                sectionTitle("最近会话", count: store.recentSessions.count)
                ForEach(store.recentSessions.prefix(6)) { session in
                    Button {
                        store.analyzeConfirmedSession(sourceFile: session.sourceFile)
                    } label: {
                        recentSessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSessionAnalyzing || store.isSessionLocating)
                }
                Text("点击任一会话即可直接通读分析，免粘贴。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func recentSessionRow(_ session: RecentSession) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.preview.isEmpty ? session.id : session.preview)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
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
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .contentShape(Rectangle())
    }

    /// Turn a Claude project dir name ("-Users-me-work") into a readable tail.
    private func sessionProject(_ raw: String) -> String {
        let parts = raw.split(separator: "-").filter { !$0.isEmpty }
        return parts.suffix(2).joined(separator: "/")
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
                Text("确认无误后再通读分析（约需 1–5 分钟）。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("或粘贴会话结尾")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .focused($composerFocused)
                if draft.isEmpty {
                    Text("粘贴 Claude terminal session 最后的几段内容…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Palette.cardStroke)
            }
            HStack {
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                        draft = draft.isEmpty ? clip : draft + "\n" + clip
                    }
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Text("\(draft.count) 字符")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("建议包含 1–2 行有辨识度的最终结论")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
