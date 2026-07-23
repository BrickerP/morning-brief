import SwiftUI

struct WorkLedgerView: View {
    @EnvironmentObject private var store: BriefStore

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
    @State private var archivedItem: WorkItem?
    @State private var showingHistory = false
    @State private var completedExpanded = false

    private var selectedItem: WorkItem? {
        guard let selectedItemID else { return nil }
        return store.work?.allItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        Group {
            if showingHistory {
                historyView
            } else if let item = archivedItem {
                detailView(item, readOnly: true)
            } else if let item = selectedItem {
                detailView(item, readOnly: store.work?.readOnly ?? !store.isViewingToday)
            } else {
                overview
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if store.isViewingToday {
                TextField("记下一件刚发生的工作…", text: $captureText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(capture)
                    .disabled(store.isWorkMutating)
                    .accessibilityLabel("快速记录工作")
                    .accessibilityHint("输入工作标题并按回车保存")
                    .onChange(of: captureText) {
                        if !store.isWorkMutating {
                            captureIdempotencyKey = nil
                        }
                    }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    workSection("进行中", items: store.work?.inProgress ?? [])
                    workSection("待处理", items: store.work?.pending ?? [])
                    completedSection
                    historyLink
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.sm)
            }

            Divider()
            workFooter
        }
    }

    private func workSection(_ title: String, items: [WorkItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            sectionLabel(title, count: items.count)
            if items.isEmpty {
                Text(title == "进行中" ? "暂无进行中的工作" : "待办已经清空")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, DS.Space.xs)
            } else {
                ForEach(items) { item in
                    WorkItemRow(item: item) {
                        selectedItemID = item.id
                    }
                }
            }
        }
    }

    private var completedSection: some View {
        let completed = store.work?.completedToday ?? []
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    completedExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(completedExpanded ? 90 : 0))
                    sectionLabel("今日完成", count: completed.count)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completedExpanded ? "收起今日完成" : "展开今日完成")

            if completedExpanded {
                ForEach(completed) { item in
                    WorkItemRow(item: item) {
                        selectedItemID = item.id
                    }
                }
            }
        }
    }

    private var historyLink: some View {
        Button {
            showingHistory = true
        } label: {
            HStack {
                Spacer()
                Text("最近 7 天记录")
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看最近七天工作记录")
    }

    private var workFooter: some View {
        HStack(spacing: DS.Space.sm) {
            if let event = store.work?.latestAgentEvent {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent 最近更新")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(event.summary)
                        .font(.caption)
                        .lineLimit(1)
                }
            } else {
                Text("暂无 Agent 更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let event = store.work?.latestReversibleEvent, store.isViewingToday {
                Button("撤销上次更新") {
                    store.undo(eventID: event.eventId)
                }
                .buttonStyle(.borderless)
                .disabled(store.isWorkMutating)
                .accessibilityHint("追加一条撤销事件，不删除历史记录")
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            navigationTitle("今日工作", title: "最近 7 天") {
                showingHistory = false
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    ForEach(store.work?.recentHistory ?? []) { day in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            HStack {
                                Text(displayDate(day.date))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("完成 \(day.completed.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(day.items) { item in
                                WorkItemRow(item: item) {
                                    archivedItem = item
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.sm)
            }
        }
    }

    private func detailView(_ item: WorkItem, readOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            navigationTitle(archivedItem == nil ? "今日工作" : "最近 7 天", title: "") {
                if archivedItem != nil {
                    archivedItem = nil
                } else {
                    selectedItemID = nil
                }
                cancelEditing()
            }

            if isEditingItem && !readOnly {
                editForm(item)
            } else {
                HStack {
                    Text("任务记录")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if readOnly {
                        WorkStatusLabel(status: item.status)
                    } else {
                        Button {
                            beginEditing(item)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.isWorkMutating)
                        .accessibilityHint("修改任务标题和说明")

                        Menu {
                            ForEach(WorkStatus.allCases) { status in
                                Button {
                                    store.setWorkStatus(
                                        itemID: item.id,
                                        status: status,
                                        version: item.version
                                    )
                                } label: {
                                    Label(status.title, systemImage: status.iconName)
                                }
                            }
                        } label: {
                            WorkStatusLabel(status: item.status, showsChevron: true)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(store.isWorkMutating)
                        .accessibilityLabel("当前状态 \(item.status.title)，选择新状态")
                    }
                }
            }

            ScrollView {
                Text(selectableTranscript(item))
                    .font(.callout)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .accessibilityLabel("任务标题、说明和全部进展")
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
                        store.appendProgress(
                            itemID: item.id,
                            text: text,
                            version: item.version,
                            idempotencyKey: idempotencyKey
                        ) {
                            if progressText.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                                progressText = ""
                                progressIdempotencyKey = nil
                                progressIdempotencyItemID = nil
                            }
                        }
                    }
                    .disabled(store.isWorkMutating)
                    .accessibilityLabel("追加工作进展")
                    .onChange(of: progressText) {
                        if !store.isWorkMutating {
                            progressIdempotencyKey = nil
                            progressIdempotencyItemID = nil
                        }
                    }

                if let event = item.events.last(where: {
                    $0.kind != "reverted"
                        && !item.isEventReverted($0)
                }) {
                    HStack {
                        Spacer()
                        Button("撤销此变更") {
                            store.undo(eventID: event.eventId)
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.isWorkMutating)
                    }
                }
            } else {
                Label("历史记录只读", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                    store.isWorkMutating
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

    private func selectableTranscript(_ item: WorkItem) -> AttributedString {
        let value = item.selectionTranscript { event in
            guard let date = event.occurredAtDate else { return "" }
            return DateFormatter.workTime.string(from: date)
        }
        var transcript = AttributedString(value)
        if let titleRange = transcript.range(of: item.title) {
            transcript[titleRange].font = .title3.bold()
        }
        return transcript
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

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func capture() {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let idempotencyKey = captureIdempotencyKey ?? "ui:add:\(UUID().uuidString)"
        captureIdempotencyKey = idempotencyKey
        store.captureWork(title: text, idempotencyKey: idempotencyKey) {
            if captureText.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                captureText = ""
                captureIdempotencyKey = nil
            }
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
        store.editWork(
            itemID: item.id,
            title: title,
            detail: detail,
            version: item.version,
            idempotencyKey: idempotencyKey
        ) {
            cancelEditing()
        }
    }

    private func resetEditIdempotencyIfPossible() {
        guard !store.isWorkMutating else { return }
        editIdempotencyKey = nil
    }

    private func progressKey(for itemID: String) -> String {
        if progressIdempotencyItemID == itemID, let progressIdempotencyKey {
            return progressIdempotencyKey
        }
        return "ui:note:\(itemID):\(UUID().uuidString)"
    }

    private func displayDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter.workDay.date(from: value) else { return value }
        return DateFormatter.workHistory.string(from: date)
    }
}

private struct WorkItemRow: View {
    let item: WorkItem
    let action: () -> Void

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
                        .foregroundStyle(item.status == .cancelled ? .secondary : .primary)
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
