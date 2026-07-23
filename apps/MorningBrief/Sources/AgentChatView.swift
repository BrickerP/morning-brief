import SwiftUI

struct AgentChatView: View {
    @EnvironmentObject private var store: BriefStore

    @State private var draft = ""
    @State private var showingApplyConfirmation = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    intro
                    if let analysis = store.sessionAnalysis {
                        pastedEnding
                        analysisView(analysis)
                    } else {
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
                store.applySessionAnalysis()
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
            Text("粘贴 terminal 中 Claude session 的结尾。Agent 会定位原始记录、通读主会话和子 Agent，再匹配今天的 Todo。分析阶段不会修改台账。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("你")
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
            .frame(minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Palette.cardStroke)
            }
            HStack {
                Text("\(draft.count) 字符")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("建议包含 1–2 行有辨识度的最终结论")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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

            if let applied = store.sessionApplyResult {
                Label(
                    "已写入 \(applied.appliedCount) 条更新",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
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
            if store.sessionAnalysis != nil {
                Button("重新开始") {
                    store.clearSessionAnalysis()
                    draft = ""
                    composerFocused = true
                }
                .buttonStyle(.borderless)
                .disabled(store.isSessionAnalyzing || store.isSessionApplying)
            }

            Spacer()

            if store.isSessionAnalyzing {
                ProgressView()
                    .controlSize(.small)
                Text("通读中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.isSessionApplying {
                ProgressView()
                    .controlSize(.small)
                Text("写入中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let analysis = store.sessionAnalysis,
                      store.sessionApplyResult == nil,
                      !analysis.proposals.isEmpty {
                Button("确认 \(analysis.proposals.count) 条更新") {
                    showingApplyConfirmation = true
                }
                .buttonStyle(.borderedProminent)
            } else if store.sessionAnalysis == nil {
                Button("定位并分析") {
                    store.analyzeClaudeSession(tail: draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
