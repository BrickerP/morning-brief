import SwiftUI

struct WorkLedgerView: View {
    @ObservedObject var appStore: Store<AppFeature.State, AppFeature.Action>

    @State private var captureText = ""
    @State private var progressText = ""
    @State private var captureIdempotencyKey: String?
    @State private var progressIdempotencyKey: String?
    @State private var progressIdempotencyItemID: String?
    @State private var isEditingItem = false
    @State private var editTitle = ""
    @State private var editDetail = ""
    @State private var editIdempotencyKey: String?
    @State private var editIdempotencyItemID: String?
    @State private var selectedItemID: String?
    @State private var pendingDeleteItem: WorkItem?
    @State private var editingProgressEventID: String?
    @State private var editProgressText = ""
    @State private var progressEditIdempotencyKey: String?
    @FocusState private var captureFocused: Bool

    private var selectedItem: WorkItem? {
        guard let selectedItemID else { return nil }
        return appStore.state.work.work?.allItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        Group {
            if let item = selectedItem {
                // Items only present in recent_history (not today's active list) are read-only.
                let inTodayItems = appStore.state.work.work?.items.contains { $0.id == item.id } ?? false
                let readOnly = (appStore.state.work.work?.readOnly ?? !appStore.state.work.isViewingToday) || !inTodayItems
                detailView(item, readOnly: readOnly)
            } else {
                overview
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // Capture + contribution calendar share one chrome block so the span chart keeps height.
            workTopChrome

            WorkDaySpanChart(
                spans: appStore.state.work.work?.daySpans() ?? [],
                highlightedItemID: appStore.state.work.highlightedItemID
            ) { item in
                selectedItemID = item.id
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: appStore.state.work.highlightedItemID)

            if appStore.state.work.isViewingToday, appStore.state.work.work?.latestReversibleEvent != nil {
                workFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(captureShortcut)
        .onAppear { focusCaptureSoon() }
        .onChange(of: selectedItemID) { _, itemID in
            if itemID == nil { focusCaptureSoon() }
        }
        .onChange(of: appStore.state.work.isViewingToday) { _, viewingToday in
            if viewingToday { focusCaptureSoon() }
        }
    }

    /// Cold-start / return-to-overview: focus after the window becomes key.
    private func focusCaptureSoon() {
        guard appStore.state.work.isViewingToday,
              !(appStore.state.work.work?.readOnly ?? false) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            captureFocused = true
        }
    }

    private var canSubmitCapture: Bool {
        !captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appStore.state.work.isMutating
    }

    /// Shared top plane height — same for today/history so the heatmap doesn't jump.
    private let workChromeBodyHeight: CGFloat = 88
    /// Today: chat keeps at least this much; remainder goes to the heatmap.
    private let workCaptureMinWidth: CGFloat = 168
    private let workCaptureWidthFraction: CGFloat = 0.40

    /// Date rail + heatmap (/ capture). History → heatmap full-bleed; today → balanced split.
    private var workTopChrome: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(appStore.state.work.displayDate)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                if !appStore.state.work.isViewingToday {
                    Button("今天") {
                        appStore.send(.work(.selectDate(BriefPaths.todayDateString())))
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Text("历史")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }

            GeometryReader { geo in
                let gap = DS.Space.sm
                if appStore.state.work.isViewingToday {
                    let chatWidth = min(
                        max(workCaptureMinWidth, geo.size.width * workCaptureWidthFraction),
                        geo.size.width * 0.48
                    )
                    let heatWidth = max(0, geo.size.width - chatWidth - gap)
                    HStack(alignment: .top, spacing: gap) {
                        activityHeatmap
                            .frame(width: heatWidth, height: geo.size.height)
                        captureComposer
                            .frame(width: chatWidth, height: geo.size.height)
                    }
                } else {
                    activityHeatmap
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: workChromeBodyHeight)
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    private var activityHeatmap: some View {
        WorkActivityHeatmap(
            selectedDate: appStore.state.work.selectedDate,
            counts: appStore.state.work.spanActivityCounts,
            preferredWeeks: 18
        ) { day in
            appStore.send(.work(.selectDate(day)))
        }
    }

    /// Full-height chat composer that matches the heatmap pane.
    private var captureComposer: some View {
        HStack(alignment: .bottom, spacing: DS.Space.sm) {
            TextField("", text: $captureText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($captureFocused)
                .onSubmit(capture)
                .disabled(appStore.state.work.isMutating)
                .accessibilityLabel("快速记录工作")
                .accessibilityHint("输入标题后回车或点发送")
                .onChange(of: captureText) {
                    if !appStore.state.work.isMutating {
                        captureIdempotencyKey = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button(action: capture) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(canSubmitCapture ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitCapture)
            .accessibilityLabel("发送")
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            captureFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(
                    captureFocused ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }

    /// Hidden ⌘N shortcut that focuses the quick-capture field.
    @ViewBuilder
    private var captureShortcut: some View {
        if appStore.state.work.isViewingToday {
            Button {
                captureFocused = true
            } label: { EmptyView() }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityHidden(true)
        }
    }

    /// Inline delete confirm — avoids a system sheet interrupting the focused flow.
    private func deleteConfirmBanner(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("删除这个任务？")
                .font(.caption.weight(.semibold))
            Text("「\(item.title)」会从台账视图中移除；事件仍保留且可撤销。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.sm) {
                Button("返回") {
                    pendingDeleteItem = nil
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button("删除", role: .destructive) {
                    applyDelete(item)
                    pendingDeleteItem = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(appStore.state.work.isMutating)
            }
        }
        .padding(DS.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var workFooter: some View {
        HStack {
            Spacer()
            if let event = appStore.state.work.work?.latestReversibleEvent {
                Button("撤销上次更新") {
                    appStore.send(.work(.undo(eventID: event.eventId)))
                }
                .buttonStyle(.borderless)
                .disabled(appStore.state.work.isMutating)
                .accessibilityHint("追加一条撤销事件，不删除历史记录")
            }
        }
    }

    /// Hidden Esc shortcut that runs a back action (detail dismissal).
    private func backShortcut(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut(.cancelAction)
            .accessibilityHidden(true)
    }

    private func detailView(_ item: WorkItem, readOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            navigationTitle("今日工作", title: "") {
                selectedItemID = nil
                cancelEditing()
                cancelProgressEditing()
            }

            if isEditingItem && !readOnly {
                editForm(item)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Spacer()
                        if !readOnly {
                            Button {
                                beginEditing(item)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .disabled(appStore.state.work.isMutating)
                            .accessibilityHint("修改任务标题和说明")
                        }
                    }
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: DS.Space.sm) {
                        if readOnly {
                            WorkStatusLabel(status: item.status)
                        } else {
                            Menu {
                                ForEach([WorkStatus.pending, .inProgress], id: \.self) { status in
                                    Button {
                                        applyStatus(item, status)
                                    } label: {
                                        Label(status.title, systemImage: status.iconName)
                                    }
                                }
                            } label: {
                                WorkStatusLabel(status: item.status, showsChevron: true)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .disabled(appStore.state.work.isMutating)
                        }
                        if let duration = item.wallClockDurationLabel {
                            Text(duration)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if let span = appStore.state.work.work?.daySpans().first(where: { $0.id == item.id }) {
                daySpanMiniBar(span)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("记录")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(item.events.filter { $0.kind != "progress_edited" }) { event in
                        taskTimelineNode(item, event: event, readOnly: readOnly)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.sm)
            }

            if !readOnly {
                TextField("追加进展、阻塞或下一步…", text: $progressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let text = progressText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        let idempotencyKey = progressKey(for: item.id)
                        progressIdempotencyKey = idempotencyKey
                        progressIdempotencyItemID = item.id
                        appStore.send(.work(.appendProgress(
                            itemID: item.id,
                            text: text,
                            version: item.version,
                            idempotencyKey: idempotencyKey
                        )))
                        if progressText.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                            progressText = ""
                            progressIdempotencyKey = nil
                            progressIdempotencyItemID = nil
                        }
                    }
                    .disabled(appStore.state.work.isMutating)
                    .accessibilityLabel("追加工作进展")
                    .onChange(of: progressText) {
                        if !appStore.state.work.isMutating {
                            progressIdempotencyKey = nil
                            progressIdempotencyItemID = nil
                        }
                    }

                if pendingDeleteItem?.id == item.id {
                    deleteConfirmBanner(item)
                } else {
                    HStack(spacing: DS.Space.sm) {
                        if item.status == .pending || item.status == .inProgress {
                            Button("完成") {
                                applyStatus(item, .completed)
                            }
                            .buttonStyle(.borderless)
                            .disabled(appStore.state.work.isMutating)

                            Button("删除…") {
                                pendingDeleteItem = item
                            }
                            .buttonStyle(.borderless)
                            .disabled(appStore.state.work.isMutating)
                            .accessibilityHint("从台账视图移除，可撤销")
                        }

                        Spacer()

                        if let event = item.events.last(where: {
                            $0.kind != "reverted"
                                && !item.isEventReverted($0)
                        }) {
                            Button("撤销此变更") {
                                appStore.send(.work(.undo(eventID: event.eventId)))
                            }
                            .buttonStyle(.borderless)
                            .disabled(appStore.state.work.isMutating)
                        }
                    }
                }
            } else {
                Label("历史记录只读", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .background(
            // Esc returns to the list — but not while editing, where the edit
            // form's own Cancel already owns the Escape key.
            Group {
                if !isEditingItem {
                    backShortcut {
                        selectedItemID = nil
                    }
                }
            }
        )
    }

    private func applyStatus(_ item: WorkItem, _ status: WorkStatus) {
        appStore.send(.work(.setStatus(itemID: item.id, status: status, version: item.version)))
        if status == .completed {
            selectedItemID = nil
        }
    }

    private func applyDelete(_ item: WorkItem) {
        appStore.send(.work(.deleteItem(
            itemID: item.id,
            version: item.version,
            idempotencyKey: "ui:delete:\(item.id):\(item.version)"
        )))
        selectedItemID = nil
    }

    private func editForm(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("标题")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("任务标题", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveEditing(item) }
                    .accessibilityLabel("任务标题")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("说明")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $editDetail)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .frame(minHeight: 64, maxHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    }
                    .accessibilityLabel("任务说明")
            }

            HStack {
                Button("取消") {
                    cancelEditing()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    saveEditing(item)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    appStore.state.work.isMutating
                        || editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .onChange(of: editTitle) {
            resetEditIdempotencyIfPossible()
        }
        .onChange(of: editDetail) {
            resetEditIdempotencyIfPossible()
        }
    }

    private func daySpanMiniBar(_ span: WorkDaySpan) -> some View {
        let tint = WorkDaySpanChart.laneTint(for: span.item.id, status: span.item.status)
        let range = span.yRange(in: 100)
        let startLabel = span.startDay.count >= 10
            ? String(span.startDay.dropFirst(5))
            : span.startDay
        let endLabel = span.endDay == BriefPaths.todayDateString()
            ? "今天"
            : (span.endDay.count >= 10 ? String(span.endDay.dropFirst(5)) : span.endDay)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Space.xs) {
                Text("日期跨度")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("\(startLabel) → \(endLabel) · \(span.spanDayCount) 天")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 8)
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(
                            width: max(8, geo.size.width * CGFloat(range.height) / 100),
                            height: 8
                        )
                        .offset(x: geo.size.width * CGFloat(range.y) / 100)
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private func taskTimelineNode(
        _ item: WorkItem,
        event: WorkEvent,
        readOnly: Bool
    ) -> some View {
        let actor = switch event.actor {
        case "human": "你"
        case "agent": "Agent"
        default: "系统"
        }
        let time: String = {
            guard let date = event.occurredAtDate else { return "" }
            return DateFormatter.workTime.string(from: date)
        }()
        let reverted = item.isEventReverted(event)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !time.isEmpty {
                    Text(time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(actor)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if reverted {
                    Text("已撤销")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !readOnly,
                   !reverted,
                   event.kind == "progress_added",
                   editingProgressEventID != event.eventId {
                    Button("编辑") {
                        beginProgressEditing(event)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appStore.state.work.isMutating)
                }
            }
            if editingProgressEventID == event.eventId, !readOnly {
                TextField("进展正文", text: $editProgressText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                HStack {
                    Button("取消") { cancelProgressEditing() }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("保存") { saveProgressEditing(item, event: event) }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            appStore.state.work.isMutating
                                || editProgressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            } else {
                Text((reverted ? "[已撤销] " : "") + item.summary(for: event))
                    .font(.callout)
                    .foregroundStyle(reverted ? .secondary : .primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func beginProgressEditing(_ event: WorkEvent) {
        if case .string(let text)? = event.payload["text"] {
            editProgressText = text
        } else {
            editProgressText = ""
        }
        editingProgressEventID = event.eventId
        progressEditIdempotencyKey = nil
    }

    private func cancelProgressEditing() {
        editingProgressEventID = nil
        editProgressText = ""
        progressEditIdempotencyKey = nil
    }

    private func saveProgressEditing(_ item: WorkItem, event: WorkEvent) {
        let text = editProgressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let key = progressEditIdempotencyKey
            ?? "ui:note-edit:\(item.id):\(event.eventId):\(UUID().uuidString)"
        progressEditIdempotencyKey = key
        appStore.send(.work(.editProgress(
            itemID: item.id,
            eventID: event.eventId,
            text: text,
            version: item.version,
            idempotencyKey: key
        )))
        cancelProgressEditing()
    }

    private func navigationTitle(_ backTitle: String, title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Label(backTitle, systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            if !title.isEmpty {
                Spacer()
                Text(title)
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 64, height: 1)
            }
        }
    }

    private func capture() {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let idempotencyKey = captureIdempotencyKey ?? "ui:add:\(UUID().uuidString)"
        captureIdempotencyKey = idempotencyKey
        appStore.send(.work(.capture(title: text, idempotencyKey: idempotencyKey)))
        if captureText.trimmingCharacters(in: .whitespacesAndNewlines) == text {
            captureText = ""
            captureIdempotencyKey = nil
        }
    }

    private func beginEditing(_ item: WorkItem) {
        editTitle = item.title
        editDetail = item.detail
        editIdempotencyKey = nil
        editIdempotencyItemID = item.id
        isEditingItem = true
    }

    private func cancelEditing() {
        isEditingItem = false
        editTitle = ""
        editDetail = ""
        editIdempotencyKey = nil
        editIdempotencyItemID = nil
    }

    private func saveEditing(_ item: WorkItem) {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let detail = editDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey: String
        if editIdempotencyItemID == item.id, let existing = editIdempotencyKey {
            idempotencyKey = existing
        } else {
            idempotencyKey = "ui:edit:\(item.id):\(UUID().uuidString)"
            editIdempotencyKey = idempotencyKey
            editIdempotencyItemID = item.id
        }
        appStore.send(.work(.editItem(
            itemID: item.id,
            title: title,
            detail: detail,
            version: item.version,
            idempotencyKey: idempotencyKey
        )))
        cancelEditing()
    }

    private func resetEditIdempotencyIfPossible() {
        guard !appStore.state.work.isMutating else { return }
        editIdempotencyKey = nil
    }

    private func progressKey(for itemID: String) -> String {
        if progressIdempotencyItemID == itemID, let progressIdempotencyKey {
            return progressIdempotencyKey
        }
        return "ui:note:\(itemID):\(UUID().uuidString)"
    }

}

private struct WorkItemRow: View {
    let item: WorkItem
    let action: () -> Void
    var onComplete: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.sm) {
                Image(systemName: item.status.iconName)
                    .foregroundStyle(item.status.tint)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let progress = item.lastProgress, !progress.isEmpty {
                        Text(progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.xs)
                if let date = item.lastEventDate {
                    Text(DateFormatter.workTime.string(from: date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.status == .pending || item.status == .inProgress {
                if let onComplete {
                    Button("标记完成") { onComplete() }
                }
                if let onDelete {
                    Button("删除…", role: .destructive) { onDelete() }
                }
            }
        }
        .accessibilityLabel("\(item.status.title)，\(item.title)")
    }
}

private struct WorkStatusLabel: View {
    let status: WorkStatus
    var showsChevron = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
            Text(status.title)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.1))
        .clipShape(Capsule())
    }
}

private extension WorkStatus {
    var tint: Color {
        switch self {
        case .pending: .secondary
        case .inProgress: .accentColor
        case .completed: .green
        case .cancelled: Color(nsColor: .systemGray)
        }
    }
}

private extension ISO8601DateFormatter {
    static let workDay: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

private extension DateFormatter {
    static let workTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = BriefPaths.dayTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let workHistory: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = BriefPaths.dayTimeZone
        formatter.dateFormat = "M 月 d 日 · EEEE"
        return formatter
    }()
}
