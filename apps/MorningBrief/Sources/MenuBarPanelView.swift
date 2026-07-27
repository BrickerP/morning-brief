import SwiftUI

private enum PanelLens: String, CaseIterable, Identifiable {
    case work
    case agent
    case brief

    var id: String { rawValue }
    var title: String {
        switch self {
        case .work: "工作台账"
        case .agent: "Agent"
        case .brief: "晨报"
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

struct MenuBarPanelView: View {
    @EnvironmentObject private var store: BriefStore
    @Environment(\.openURL) private var openURL

    @State private var isFullExpanded = false
    @State private var fullContentOpacity: Double = 0
    @State private var highlightedSectionID: String?
    @AppStorage("MorningBrief.selectedLens") private var selectedLensRaw = PanelLens.brief.rawValue
    @AppStorage("MorningBrief.lastSeenAgentEvent") private var lastSeenAgentEventID = ""
    @AppStorage("MorningBrief.lastSeenBriefStamp") private var lastSeenBriefStamp = ""

    private var selectedLens: PanelLens {
        get { PanelLens(rawValue: selectedLensRaw) ?? .brief }
        nonmutating set { selectedLensRaw = newValue.rawValue }
    }

    private var hasContent: Bool { store.brief?.hasReadableContent ?? false }
    private var readableSections: [BriefSection] { store.brief?.readableSections ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            titleBar
            noticeBanner
            if selectedLens == .work {
                WorkLedgerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedLens == .agent {
                dateChrome
                AgentChatView()
            } else {
                dateChrome
                Group {
                    if hasContent {
                        contentScroll
                    } else {
                        emptyState
                    }
                }
                footer
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 460, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedLens == .work {
                store.refreshWorkProjection()
                markAgentUpdateSeen()
            } else if selectedLens == .agent {
                store.loadRecentSessions()
            } else if selectedLens == .brief {
                markBriefSeen()
            }
        }
        .onChange(of: selectedLensRaw) {
            if selectedLens == .work {
                store.refreshWorkProjection()
                markAgentUpdateSeen()
            } else if selectedLens == .agent {
                store.loadRecentSessions()
            } else if selectedLens == .brief {
                markBriefSeen()
            }
        }
        .onChange(of: store.work?.latestAgentEvent?.eventId) {
            if selectedLens == .work { markAgentUpdateSeen() }
        }
        .onChange(of: store.brief?.generatedAt) {
            if selectedLens == .brief { markBriefSeen() }
        }
    }

    private var lensPicker: some View {
        Picker("视图", selection: Binding(
            get: { selectedLens },
            set: { selectedLens = $0 }
        )) {
            ForEach(PanelLens.allCases) { lens in
                HStack(spacing: 5) {
                    Text(lens.title)
                    if lens == .work, hasUnreadAgentUpdate {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }
                    if lens == .brief, hasUnreadBrief {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }
                }
                .tag(lens)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("在工作台账、Agent 和晨报之间切换")
    }

    private var hasUnreadAgentUpdate: Bool {
        guard let eventID = store.work?.latestAgentEvent?.eventId else { return false }
        return eventID != lastSeenAgentEventID
    }

    private func markAgentUpdateSeen() {
        if let eventID = store.work?.latestAgentEvent?.eventId {
            lastSeenAgentEventID = eventID
        }
    }

    /// A fresh brief the user hasn't opened yet — identified by its generation
    /// timestamp so a re-synthesized brief re-flags. Empty briefs never flag.
    private var hasUnreadBrief: Bool {
        guard store.isViewingToday,
              let stamp = store.brief?.generatedAt, !stamp.isEmpty,
              hasContent else { return false }
        return stamp != lastSeenBriefStamp
    }

    private func markBriefSeen() {
        if store.isViewingToday, let stamp = store.brief?.generatedAt, !stamp.isEmpty {
            lastSeenBriefStamp = stamp
        }
    }

    // MARK: Header

    /// Brand + lens switcher on one row so tabs sit with the product name.
    private var titleBar: some View {
        HStack(alignment: .center, spacing: DS.Space.sm) {
            Text("Morning Brief")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            lensPicker
                .frame(maxWidth: 260)
        }
    }

    /// Compact date + contribution grid (Agent / 晨报). Work lens owns its own chrome with capture.
    private var dateChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            dateMetaRow
            WorkActivityHeatmap(
                selectedDate: store.selectedDate,
                counts: store.work?.spanActivityCounts(
                    endingAt: BriefPaths.todayDateString(),
                    weeks: 26
                ) ?? [:],
                preferredWeeks: 18
            ) { day in
                store.select(date: day)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
        }
    }

    private var dateMetaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(store.displayDate)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if !store.isViewingToday {
                Button("今天") {
                    store.select(date: BriefPaths.todayDateString())
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                tinyBadge("历史", background: Color.secondary.opacity(0.15))
            } else if selectedLens == .brief, hasContent && store.isStale {
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
        if let notice = store.notice, !notice.isEmpty {
            HStack(spacing: 6) {
                if store.isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        if let error = store.errorMessage, !error.isEmpty {
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
                    if let hero = store.brief?.hero, hero.hasContent {
                        heroBlock(hero, proxy: proxy)
                        if !readableSections.isEmpty {
                            Divider()
                            disclosure(proxy: proxy)
                        }
                    } else {
                        sectionsList(proxy: proxy)
                        sourceChips
                    }
                }
                .padding(.bottom, 8)
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

    // MARK: 全文 disclosure

    @ViewBuilder
    private func disclosure(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                toggleFull()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFullExpanded ? 90 : 0))
                    Text("全文")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(readableSections.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFullExpanded ? "收起全文" : "展开全文")

            if isFullExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    sectionsList(proxy: proxy)
                    sourceChips
                    synthFootnote
                }
                .opacity(fullContentOpacity)
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
        if let chips = store.run?.sourceChips, !chips.isEmpty {
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
        if let synth = store.brief?.synthBadge, !synth.isEmpty {
            Text("合成 \(synth)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if store.isRefreshing || store.isSynthesizing {
                Button(role: .cancel) {
                    store.cancelPipeline()
                } label: {
                    Label(store.isSynthesizing ? "合成中… 取消" : "更新中… 取消", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                Button {
                    store.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut("r")
                .disabled(store.isBusy || !store.isViewingToday)

                Button("合成") {
                    store.synthesize()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isBusy || !store.isViewingToday)
            }

            Spacer()

            Menu {
                Button("Doctor") {
                    store.doctor()
                }
                .disabled(store.isDoctorRunning)
                Button("打开文件夹") {
                    store.openFolder()
                }
                Divider()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
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
        expandFull()
        // Wait for the expand spring + content fade before scrolling to the target.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(sectionId, anchor: .top)
            }
            highlight(sectionId)
        }
    }

    private func toggleFull() {
        isFullExpanded ? collapseFull() : expandFull()
    }

    private func expandFull() {
        guard !isFullExpanded else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isFullExpanded = true
        }
        // Content opacity lags the row/chevron by ~40ms.
        fullContentOpacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.easeIn(duration: 0.22)) {
                fullContentOpacity = 1
            }
        }
    }

    private func collapseFull() {
        guard isFullExpanded else { return }
        // Fade the content out first, then collapse the container.
        withAnimation(.easeOut(duration: 0.12)) {
            fullContentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                isFullExpanded = false
            }
        }
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
