import SwiftUI

enum PanelLens: String, CaseIterable, Identifiable, Hashable {
    case work
    case agent
    case brief

    static let storageKey = "MorningBrief.selectedLens"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "工作台账"
        case .agent: "Agent"
        case .brief: "晨报"
        }
    }

    var symbol: String {
        switch self {
        case .work: "checklist"
        case .agent: "bubble.left.and.bubble.right"
        case .brief: "newspaper"
        }
    }
}

struct SourceChipView: View {
    let source: BriefSourceChip

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(source.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
        .accessibilityLabel("\(source.name), \(source.status.rawValue)")
    }

    private var color: Color {
        switch source.status {
        case .ok, .synthesized: .green
        case .partial, .empty: .orange
        case .failed: .red
        case .unknown: .gray
        }
    }
}

struct BriefSectionView: View {
    let section: BriefSection
    var isHighlighted: Bool = false

    private var style: SectionStyle { SectionStyle.forKind(section.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: style.symbol)
                    .font(.subheadline)
                    .foregroundStyle(style.tint)
                    .frame(width: 18)
                Text(section.title)
                    .font(DS.Typo.sectionTitle)
            }
            MarkdownView(markdown: section.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(isHighlighted ? Color.accentColor.opacity(0.14) : DS.Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(isHighlighted ? Color.accentColor.opacity(0.4) : DS.Palette.cardStroke)
        )
    }
}

/// One tappable must-read row in the hero.
struct MustReadRow: View {
    let mustRead: HeroMustRead
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mustRead.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = mustRead.summary,
                       !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if mustRead.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if mustRead.sectionId != nil {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering = $0 }
        .accessibilityLabel(mustRead.title)
    }
}

struct RootWindowView: View {
    @ObservedObject var appStore: Store<AppFeature.State, AppFeature.Action>
    @Environment(\.openURL) private var openURL

    @State private var highlightedSectionID: String?
    @AppStorage("MorningBrief.lastSeenAgentEvent") private var lastSeenAgentEventID = ""
    @AppStorage("MorningBrief.lastSeenBriefStamp") private var lastSeenBriefStamp = ""

    private var selectedLens: PanelLens { appStore.state.lens }
    private var brief: BriefFeature.State { appStore.state.brief }

    private var hasContent: Bool { brief.brief?.hasReadableContent ?? false }
    private var readableSections: [BriefSection] { brief.brief?.readableSections ?? [] }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: AppChrome.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(AppChrome.sidebarFill.opacity(0.92))

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: DS.Space.sm) {
                detailPane
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 880, minHeight: 600)
        .tint(AppChrome.accent)
        .onAppear { handleLensAppear() }
        .onChange(of: appStore.state.lens) {
            handleLensAppear()
            // Lens swaps can drop key/on-screen ordering (seen when jumping to 晨报).
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        .onChange(of: appStore.state.work.work?.latestAgentEvent?.eventId) {
            if selectedLens == .work { markAgentUpdateSeen() }
        }
        .onChange(of: brief.brief?.generatedAt) {
            if selectedLens == .brief { markBriefSeen() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Morning Brief")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.top, 8)

            VStack(spacing: 4) {
                ForEach(PanelLens.allCases) { lens in
                    GlassSidebarTab(
                        lens: lens,
                        selected: selectedLens == lens,
                        showDot: (lens == .work && hasUnreadAgentUpdate)
                            || (lens == .brief && hasUnreadBrief)
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appStore.send(.setLens(lens))
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder
    private var detailPane: some View {
        noticeBanner
        switch selectedLens {
        case .work:
            WorkLedgerView(appStore: appStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { appStore.send(.work(.onAppear)) }
        case .agent:
            dateMetaRow
            AgentChatView(appStore: appStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .brief:
            dateMetaRow
            Group {
                if hasContent {
                    contentScroll
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
    }

    private func handleLensAppear() {
        switch selectedLens {
        case .work:
            appStore.send(.work(.onAppear))
            markAgentUpdateSeen()
        case .agent:
            appStore.send(.brief(.syncDateFromWork(appStore.state.work.selectedDate)))
            appStore.send(.agent(.onAppear))
        case .brief:
            appStore.send(.brief(.syncDateFromWork(appStore.state.work.selectedDate)))
            appStore.send(.brief(.onAppear))
            markBriefSeen()
        }
    }

    private var hasUnreadAgentUpdate: Bool {
        guard let eventID = appStore.state.work.work?.latestAgentEvent?.eventId else { return false }
        return eventID != lastSeenAgentEventID
    }

    private func markAgentUpdateSeen() {
        if let eventID = appStore.state.work.work?.latestAgentEvent?.eventId {
            lastSeenAgentEventID = eventID
        }
    }

    /// A fresh brief the user hasn't opened yet — identified by its generation
    /// timestamp so a re-synthesized brief re-flags. Empty briefs never flag.
    private var hasUnreadBrief: Bool {
        guard brief.isViewingToday,
              let stamp = brief.brief?.generatedAt, !stamp.isEmpty,
              hasContent else { return false }
        return stamp != lastSeenBriefStamp
    }

    private func markBriefSeen() {
        if brief.isViewingToday, let stamp = brief.brief?.generatedAt, !stamp.isEmpty {
            lastSeenBriefStamp = stamp
        }
    }

    /// Compact date rail for Agent / 晨报 (no commit heatmap).
    private var dateMetaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(brief.displayDate)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if !brief.isViewingToday {
                Button("今天") {
                    let today = BriefPaths.todayDateString()
                    appStore.send(.work(.selectDate(today)))
                    appStore.send(.brief(.selectDate(today)))
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                tinyBadge("历史", background: Color.secondary.opacity(0.15))
            } else if selectedLens == .brief, hasContent && brief.isStale {
                tinyBadge("陈旧", background: Color.orange.opacity(0.2))
            }
            Spacer(minLength: 0)
        }
    }

    private func tinyBadge(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(Capsule())
    }

    // MARK: Notices

    @ViewBuilder
    private var noticeBanner: some View {
        let workNotice = appStore.state.work.notice
        let workError = appStore.state.work.errorMessage
        let agentNotice = appStore.state.agent.notice
        let agentError = appStore.state.agent.errorMessage
        let notice: String? = {
            switch selectedLens {
            case .work: workNotice
            case .agent: agentNotice
            case .brief: brief.notice
            }
        }()
        let error: String? = {
            switch selectedLens {
            case .work: workError
            case .agent: agentError
            case .brief: brief.errorMessage
            }
        }()
        let agentBusy = appStore.state.agent.isSessionLocating
            || appStore.state.agent.isSessionAnalyzing
            || appStore.state.agent.isSessionApplying
        if let notice, !notice.isEmpty {
            HStack(spacing: 6) {
                if brief.isBusy || appStore.state.work.isMutating || agentBusy {
                    ProgressView().controlSize(.small)
                }
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        if let error, !error.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(6)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("今天没什么")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Content

    private var contentScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let hero = brief.brief?.hero, hero.hasContent {
                        heroBlock(hero, proxy: proxy)
                        if !readableSections.isEmpty {
                            Divider()
                            sectionsList(proxy: proxy)
                            sourceChips
                            synthFootnote
                        }
                    } else {
                        sectionsList(proxy: proxy)
                        sourceChips
                        synthFootnote
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
    }

    private func heroBlock(_ hero: BriefHero, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hero.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(hero.headline)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let items = Array(hero.mustReads.prefix(3))
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        MustReadRow(mustRead: items[index]) {
                            handleMustRead(items[index], proxy: proxy)
                        }
                        if index < items.count - 1 {
                            Divider().padding(.leading, 6)
                        }
                    }
                }
            }
        }
    }

    private func sectionsList(proxy: ScrollViewProxy) -> some View {
        let sections = readableSections
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(sections) { section in
                BriefSectionView(
                    section: section,
                    isHighlighted: highlightedSectionID == section.id
                )
                .id(section.id)
            }
        }
    }

    @ViewBuilder
    private var sourceChips: some View {
        if let chips = brief.run?.sourceChips, !chips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("来源")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips) { chip in
                            SourceChipView(source: chip)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var synthFootnote: some View {
        if let synth = brief.brief?.synthBadge, !synth.isEmpty {
            Text("合成 \(synth)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if brief.isRefreshing || brief.isSynthesizing {
                Button(role: .cancel) {
                    appStore.send(.brief(.cancelPipeline))
                } label: {
                    Label(brief.isSynthesizing ? "合成中… 取消" : "更新中… 取消", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button {
                    appStore.send(.brief(.refresh))
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut("r")
                .disabled(brief.isBusy || !brief.isViewingToday)

                Button("合成") {
                    appStore.send(.brief(.synthesize))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(brief.isBusy || !brief.isViewingToday)
            }

            Spacer()

            Menu {
                Button("Doctor") {
                    appStore.send(.brief(.doctor))
                }
                .disabled(brief.isDoctorRunning)
                Button("打开文件夹") {
                    appStore.send(.brief(.openFolder))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("更多操作")
        }
    }

    // MARK: Interactions

    private func handleMustRead(_ mustRead: HeroMustRead, proxy: ScrollViewProxy) {
        if let urlString = mustRead.url,
           let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            openURL(url)
            return
        }
        guard let sectionId = mustRead.sectionId,
              readableSections.contains(where: { $0.id == sectionId }) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(sectionId, anchor: .top)
        }
        highlight(sectionId)
    }

    private func highlight(_ id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            highlightedSectionID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.4)) {
                if highlightedSectionID == id {
                    highlightedSectionID = nil
                }
            }
        }
    }
}
