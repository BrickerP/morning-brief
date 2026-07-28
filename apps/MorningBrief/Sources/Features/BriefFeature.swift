import AppKit
import Foundation

enum BriefFeature {
    static let pipelineEffectID = "brief.pipeline"

    struct State {
        var selectedDate: String = BriefPaths.todayDateString()
        var displayDate: String = BriefPaths.todayDateString()
        var lastKnownToday: String = BriefPaths.todayDateString()
        var brief: BriefDocument?
        var run: RunDocument?
        var isStale = false
        var isRefreshing = false
        var isSynthesizing = false
        var isDoctorRunning = false
        var notice: String?
        var errorMessage: String?

        var isBusy: Bool { isRefreshing || isSynthesizing }
        var isViewingToday: Bool { selectedDate == lastKnownToday }
    }

    enum Action {
        case onAppear
        case selectDate(String)
        case syncDateFromWork(String)
        case refresh
        case synthesize
        case cancelPipeline
        case doctor
        case openFolder
        case diskChanged
        case clearNotice

        // Internal
        case diskReloaded(
            brief: BriefDocument?,
            run: RunDocument?,
            displayDate: String,
            isStale: Bool,
            lastKnownToday: String
        )
        case pipelineFinished(notice: String?)
        case doctorFinished(notice: String?)
        case failed(String)
    }

    static func reduce(
        into state: inout State,
        action: Action,
        client: BriefctlClient
    ) -> Effect<Action> {
        switch action {
        case .onAppear:
            BriefWatchHost.bind(date: state.selectedDate)
            return reloadEffect(date: state.selectedDate)

        case let .selectDate(day), let .syncDateFromWork(day):
            guard day != state.selectedDate else { return .none }
            state.selectedDate = day
            state.errorMessage = nil
            BriefWatchHost.bind(date: day)
            return reloadEffect(date: day)

        case .refresh:
            guard !state.isBusy, state.isViewingToday else { return .none }
            state.isRefreshing = true
            state.errorMessage = nil
            state.notice = "正在更新…"
            return pipelineEffect(command: .runFetchOnly, client: client)

        case .synthesize:
            guard !state.isBusy, state.isViewingToday else { return .none }
            state.isSynthesizing = true
            state.errorMessage = nil
            state.notice = "正在更新…"
            return pipelineEffect(command: .synth, client: client)

        case .cancelPipeline:
            state.notice = "已取消"
            state.isRefreshing = false
            state.isSynthesizing = false
            return .cancel(id: pipelineEffectID)

        case .doctor:
            guard !state.isDoctorRunning else { return .none }
            state.isDoctorRunning = true
            state.notice = nil
            state.errorMessage = nil
            return .run {
                do {
                    let result = try await client.run(.doctor)
                    let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    return [.doctorFinished(notice: text)]
                } catch {
                    return [.failed(error.localizedDescription)]
                }
            }

        case .openFolder:
            let directory = BriefPaths.dayDirectory(forDateString: state.selectedDate)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
            return .none

        case .diskChanged:
            return reloadEffect(date: state.selectedDate)

        case let .diskReloaded(brief, run, displayDate, isStale, lastKnownToday):
            state.brief = brief
            state.run = run
            state.displayDate = displayDate
            state.isStale = isStale
            state.lastKnownToday = lastKnownToday
            return .none

        case let .pipelineFinished(notice):
            state.isRefreshing = false
            state.isSynthesizing = false
            state.notice = notice
            return reloadEffect(date: state.selectedDate)

        case let .doctorFinished(notice):
            state.isDoctorRunning = false
            state.notice = notice
            return .none

        case let .failed(message):
            state.isRefreshing = false
            state.isSynthesizing = false
            state.isDoctorRunning = false
            state.errorMessage = message
            state.notice = nil
            return .none

        case .clearNotice:
            state.notice = nil
            return .none
        }
    }

    private static func reloadEffect(date: String) -> Effect<Action> {
        .run {
            let snapshot = BriefDisk.load(date: date)
            return [
                .diskReloaded(
                    brief: snapshot.brief,
                    run: snapshot.run,
                    displayDate: snapshot.displayDate,
                    isStale: snapshot.isStale,
                    lastKnownToday: BriefPaths.todayDateString()
                ),
            ]
        }
    }

    private static func pipelineEffect(
        command: BriefctlCommand,
        client: BriefctlClient
    ) -> Effect<Action> {
        .run(id: pipelineEffectID) {
            do {
                let result = try await client.run(command)
                if result.isAlreadyRunning {
                    return [.pipelineFinished(notice: "已在生成")]
                }
                return [.pipelineFinished(notice: "已更新")]
            } catch is CancellationError {
                return [.pipelineFinished(notice: "已取消")]
            } catch let error as BriefctlError {
                if case .failed(let code, _) = error, code == 75 {
                    return [.pipelineFinished(notice: "已在生成")]
                }
                return [.failed(error.localizedDescription)]
            } catch {
                return [.failed(error.localizedDescription)]
            }
        }
    }
}

enum BriefDisk {
    static func load(date: String) -> (
        brief: BriefDocument?,
        run: RunDocument?,
        displayDate: String,
        isStale: Bool
    ) {
        let directory = BriefPaths.dayDirectory(forDateString: date)
        let displayDate = directory.lastPathComponent
        let decoder = JSONDecoder()

        var brief: BriefDocument?
        let briefURL = BriefPaths.briefJSON(in: directory)
        if let data = try? Data(contentsOf: briefURL) {
            brief = try? decoder.decode(BriefDocument.self, from: data)
        }

        var run: RunDocument?
        let runURL = BriefPaths.runJSON(in: directory)
        if let data = try? Data(contentsOf: runURL) {
            run = try? decoder.decode(RunDocument.self, from: data)
        }

        return (brief, run, displayDate, computeStaleness(brief))
    }

    private static func computeStaleness(_ brief: BriefDocument?) -> Bool {
        guard let generated = brief?.generatedAtDate else { return brief == nil }
        let threshold = brief?.stalenessHours ?? 36
        let hours = Date().timeIntervalSince(generated) / 3600
        return hours > threshold
    }
}

/// FSEvents bridge outside MiniTCA state (class lifetime). Main-thread only.
enum BriefWatchHost {
    nonisolated(unsafe) private static var watcher: BriefWatcher?
    nonisolated(unsafe) private static var onChange: (() -> Void)?

    static func setHandler(_ handler: @escaping () -> Void) {
        onChange = handler
        if watcher == nil {
            watcher = BriefWatcher {
                onChange?()
            }
        }
    }

    static func bind(date: String) {
        let directory = BriefPaths.dayDirectory(forDateString: date)
        if watcher == nil {
            watcher = BriefWatcher {
                onChange?()
            }
        }
        watcher?.watch(directory: directory)
    }
}
