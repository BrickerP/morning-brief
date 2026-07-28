import Foundation

enum WorkFeature {
    struct State {
        var selectedDate: String = BriefPaths.todayDateString()
        var displayDate: String = BriefPaths.todayDateString()
        var lastKnownToday: String = BriefPaths.todayDateString()
        var work: WorkDocument?
        var spanActivityCounts: [String: Int] = [:]
        var isMutating = false
        var notice: String?
        var errorMessage: String?
        /// Flash a newly captured item in the span chart.
        var highlightedItemID: String?

        var isViewingToday: Bool { selectedDate == lastKnownToday }
        var dayDirectory: URL { BriefPaths.dayDirectory(forDateString: selectedDate) }
    }

    enum Action {
        case onAppear
        case selectDate(String)
        case refreshProjection
        case capture(title: String, idempotencyKey: String)
        case setStatus(itemID: String, status: WorkStatus, version: Int)
        case editItem(itemID: String, title: String, detail: String, version: Int, idempotencyKey: String)
        case appendProgress(itemID: String, text: String, version: Int, idempotencyKey: String)
        case editProgress(itemID: String, eventID: String, text: String, version: Int, idempotencyKey: String)
        case deleteItem(itemID: String, version: Int, idempotencyKey: String)
        case undo(eventID: String)
        case clearNotice
        case clearHighlight

        // Internal
        case projectionResponse(WorkDocument, selectedDate: String, updateHeatmap: Bool)
        case diskReloaded(work: WorkDocument?, displayDate: String, heatmap: [String: Int]?)
        case mutationFinished(notice: String?)
        case failed(String)
        case heatmapUpdated([String: Int])
    }

    static func reduce(
        into state: inout State,
        action: Action,
        client: BriefctlClient
    ) -> Effect<Action> {
        switch action {
        case .onAppear:
            return .run { [.refreshProjection] }

        case let .selectDate(day):
            guard day != state.selectedDate else { return .none }
            state.selectedDate = day
            state.errorMessage = nil
            let loaded = loadFromDisk(date: day)
            state.work = loaded.work
            state.displayDate = loaded.displayDate
            // Heatmap stays unless we are viewing today (then disk may refresh it).
            if state.isViewingToday, let heat = loaded.heatmap {
                state.spanActivityCounts = heat
            }
            return .run { [date = state.selectedDate, viewingToday = state.isViewingToday] in
                var actions: [Action] = [.refreshProjection]
                if !viewingToday {
                    // Keep green cells from today's ledger while browsing empty history.
                    if let todayDoc = try? await client.todoView(date: nil, days: 7) {
                        let counts = todayDoc.spanActivityCounts(
                            endingAt: BriefPaths.todayDateString(),
                            weeks: 26
                        )
                        actions.insert(.heatmapUpdated(counts), at: 0)
                        actions.insert(
                            .projectionResponse(todayDoc, selectedDate: date, updateHeatmap: false),
                            at: 0
                        )
                    }
                }
                return actions
            }

        case .refreshProjection:
            let requested = state.selectedDate
            let requestingToday = requested == state.lastKnownToday
            return .run {
                do {
                    let document = try await client.todoView(
                        date: requestingToday ? nil : requested,
                        days: 7
                    )
                    return [
                        .projectionResponse(
                            document,
                            selectedDate: requested,
                            updateHeatmap: requestingToday
                        ),
                    ]
                } catch {
                    return [.failed(error.localizedDescription)]
                }
            }

        case let .projectionResponse(document, selectedDate, updateHeatmap):
            if updateHeatmap {
                state.lastKnownToday = document.date
                state.spanActivityCounts = document.spanActivityCounts(
                    endingAt: BriefPaths.todayDateString(),
                    weeks: 26
                )
                if state.selectedDate == selectedDate {
                    state.selectedDate = document.date
                }
            }
            guard state.selectedDate == selectedDate
                || (updateHeatmap && state.selectedDate == state.lastKnownToday)
            else { return .none }
            let loaded = loadFromDisk(date: state.selectedDate)
            state.work = loaded.work ?? (updateHeatmap ? document : state.work)
            state.displayDate = loaded.displayDate
            if updateHeatmap, state.isViewingToday {
                state.spanActivityCounts = document.spanActivityCounts(
                    endingAt: BriefPaths.todayDateString(),
                    weeks: 26
                )
            }
            return .none

        case let .heatmapUpdated(counts):
            state.spanActivityCounts = counts
            return .none

        case let .diskReloaded(work, displayDate, heatmap):
            state.work = work
            state.displayDate = displayDate
            if let heatmap { state.spanActivityCounts = heatmap }
            return .none

        case let .capture(title, key):
            return mutation(
                &state,
                client: client,
                command: .todoAdd(title: title, idempotencyKey: key),
                notice: "已记录"
            )

        case let .setStatus(itemID, status, version):
            let notice: String = status == .completed ? "已完成" : "状态已更新"
            return mutation(
                &state,
                client: client,
                command: .todoStatus(id: itemID, status: status, expectedVersion: version),
                notice: notice
            )

        case let .editItem(itemID, title, detail, version, key):
            return mutation(
                &state,
                client: client,
                command: .todoEdit(
                    id: itemID,
                    title: title,
                    detail: detail,
                    expectedVersion: version,
                    idempotencyKey: key
                ),
                notice: "任务已更新"
            )

        case let .appendProgress(itemID, text, version, key):
            return mutation(
                &state,
                client: client,
                command: .todoNote(
                    id: itemID,
                    text: text,
                    expectedVersion: version,
                    idempotencyKey: key
                ),
                notice: "进展已追加"
            )

        case let .editProgress(itemID, eventID, text, version, key):
            return mutation(
                &state,
                client: client,
                command: .todoNoteEdit(
                    id: itemID,
                    eventID: eventID,
                    text: text,
                    expectedVersion: version,
                    idempotencyKey: key
                ),
                notice: "进展已更新"
            )

        case let .deleteItem(itemID, version, key):
            return mutation(
                &state,
                client: client,
                command: .todoDelete(id: itemID, expectedVersion: version, idempotencyKey: key),
                notice: "已删除"
            )

        case let .undo(eventID):
            let expectedVersion: Int
            if let latest = state.work?.latestReversible, latest.event.eventId == eventID {
                expectedVersion = latest.expectedVersion
            } else if let item = state.work?.allItems.first(where: {
                $0.events.contains { $0.eventId == eventID }
            }) {
                expectedVersion = item.version
            } else {
                state.errorMessage = "找不到要撤销的变更"
                return .none
            }
            return mutation(
                &state,
                client: client,
                command: .todoUndo(eventID: eventID, expectedVersion: expectedVersion),
                notice: "已撤销"
            )

        case .clearNotice:
            state.notice = nil
            return .none

        case .clearHighlight:
            state.highlightedItemID = nil
            return .none

        case let .mutationFinished(notice):
            let previousIDs = Set(state.work?.items.map(\.id) ?? [])
            state.isMutating = false
            state.notice = notice
            let loaded = loadFromDisk(date: state.selectedDate)
            state.work = loaded.work
            state.displayDate = loaded.displayDate
            if state.isViewingToday, let heat = loaded.heatmap {
                state.spanActivityCounts = heat
            }
            if notice == "已记录",
               let newID = loaded.work?.items.map(\.id).first(where: { !previousIDs.contains($0) }) {
                state.highlightedItemID = newID
                return .sequence(
                    .run { [.refreshProjection] },
                    .run(id: "work.highlight") {
                        try? await Task.sleep(nanoseconds: 1_250_000_000)
                        return [.clearHighlight]
                    }
                )
            }
            return .run { [.refreshProjection] }

        case let .failed(message):
            state.isMutating = false
            state.errorMessage = message
            return .none
        }
    }

    private static func mutation(
        _ state: inout State,
        client: BriefctlClient,
        command: BriefctlCommand,
        notice: String
    ) -> Effect<Action> {
        guard !state.isMutating else { return .none }
        state.isMutating = true
        state.errorMessage = nil
        return .run {
            do {
                try await client.mutate(command)
                return [.mutationFinished(notice: notice)]
            } catch {
                return [.failed(error.localizedDescription)]
            }
        }
    }

    private static func loadFromDisk(date: String) -> (
        work: WorkDocument?,
        displayDate: String,
        heatmap: [String: Int]?
    ) {
        let directory = BriefPaths.dayDirectory(forDateString: date)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workURL = BriefPaths.workJSON(in: directory)
        var work: WorkDocument?
        if let data = try? Data(contentsOf: workURL) {
            work = try? JSONDecoder().decode(WorkDocument.self, from: data)
        }
        let heatmap = work.map {
            $0.spanActivityCounts(endingAt: BriefPaths.todayDateString(), weeks: 26)
        }
        return (work, directory.lastPathComponent, heatmap)
    }
}
