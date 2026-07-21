import AppKit
import Foundation
import SwiftUI

@MainActor
final class BriefStore: ObservableObject {
    @Published private(set) var status: BriefStatus = .idle
    @Published private(set) var brief: BriefDocument?
    @Published private(set) var run: RunDocument?
    @Published private(set) var displayDate: String = ""
    @Published private(set) var isStale = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSynthesizing = false
    @Published private(set) var isDoctorRunning = false

    /// Day currently being viewed (`yyyy-MM-dd`). Defaults to today in `BriefPaths.dayTimeZone`.
    @Published private(set) var selectedDate: String = BriefPaths.todayDateString()
    /// Day keys with artifacts on disk, sorted ascending.
    @Published private(set) var availableDates: [String] = []

    /// True while any pipeline command (fetch or synth) is running.
    var isBusy: Bool { isRefreshing || isSynthesizing }

    /// True when `selectedDate` is today; pipeline commands only operate on today.
    var isViewingToday: Bool { selectedDate == BriefPaths.todayDateString() }

    @Published var notice: String?
    @Published var errorMessage: String?

    private let runner = BriefctlRunner()
    private var watcher: BriefWatcher!
    private let decoder = JSONDecoder()
    private var noticeClearTask: Task<Void, Never>?

    private var dayDirectory: URL { BriefPaths.dayDirectory(forDateString: selectedDate) }

    /// Selectable days for navigation: available days plus today (even if empty), sorted ascending.
    private var navigableDates: [String] {
        var set = Set(availableDates)
        set.insert(BriefPaths.todayDateString())
        return set.sorted()
    }

    var canSelectPreviousDate: Bool {
        guard let idx = navigableDates.firstIndex(of: selectedDate) else { return !navigableDates.isEmpty }
        return idx > 0
    }

    var canSelectNextDate: Bool {
        let dates = navigableDates
        guard let idx = dates.firstIndex(of: selectedDate) else { return !dates.isEmpty }
        return idx < dates.count - 1
    }

    init() {
        watcher = BriefWatcher { [weak self] in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        refreshAvailableDates()
        reloadFromDisk()
        watcher.watch(directory: dayDirectory)
    }

    deinit {
        watcher?.stop()
    }

    var statusIcon: String { status.iconName }

    private func refreshAvailableDates() {
        availableDates = BriefPaths.availableDates()
    }

    /// Switch the viewed day: reload from that day's dir and re-point the watcher.
    func select(date: String) {
        guard date != selectedDate else { return }
        selectedDate = date
        reloadFromDisk()
        watcher.watch(directory: dayDirectory)
    }

    /// Move to the previous (earlier) available day; stays put before the earliest.
    func selectPreviousDate() {
        let dates = navigableDates
        guard let idx = dates.firstIndex(of: selectedDate) else {
            if let first = dates.first { select(date: first) }
            return
        }
        guard idx > 0 else { return }
        select(date: dates[idx - 1])
    }

    /// Move to the next (later) available day; stays put past the latest.
    func selectNextDate() {
        let dates = navigableDates
        guard let idx = dates.firstIndex(of: selectedDate) else {
            if let last = dates.last { select(date: last) }
            return
        }
        guard idx < dates.count - 1 else { return }
        select(date: dates[idx + 1])
    }

    func reloadFromDisk() {
        let directory = dayDirectory
        displayDate = directory.lastPathComponent

        var loadedBrief: BriefDocument?
        let briefURL = BriefPaths.briefJSON(in: directory)
        if let data = try? Data(contentsOf: briefURL) {
            do {
                loadedBrief = try decoder.decode(BriefDocument.self, from: data)
            } catch {
                errorMessage = "brief.json 解析失败: \(error.localizedDescription)"
            }
        }
        brief = loadedBrief

        var runStatus: BriefStatus?
        var loadedRun: RunDocument?
        let runURL = BriefPaths.runJSON(in: directory)
        if let data = try? Data(contentsOf: runURL),
           let runDoc = try? decoder.decode(RunDocument.self, from: data) {
            loadedRun = runDoc
            runStatus = runDoc.briefStatus
        }
        run = loadedRun

        isStale = computeStaleness(for: loadedBrief)

        if isBusy {
            status = .running
        } else if let runStatus {
            status = runStatus
        } else if let loadedBrief {
            status = BriefStatus(runStatus: loadedBrief.status)
        } else {
            status = .idle
        }
    }

    /// Fetch-only refresh (no agent synthesis). Only operates on today.
    func refresh() {
        guard !isBusy, isViewingToday else { return }
        isRefreshing = true
        runCommand(.runFetchOnly) { [weak self] in self?.isRefreshing = false }
    }

    /// Synthesize the brief from already-fetched sources via the agent. Only operates on today.
    func synthesize() {
        guard !isBusy, isViewingToday else { return }
        isSynthesizing = true
        runCommand(.synth) { [weak self] in self?.isSynthesizing = false }
    }

    private func runCommand(_ command: BriefctlCommand, done: @escaping () -> Void) {
        status = .running
        errorMessage = nil
        noticeClearTask?.cancel()
        notice = "正在更新…"

        Task {
            var succeeded = false
            var alreadyRunning = false
            defer {
                done()
                // briefctl always writes today's folder; pick up any newly created day.
                refreshAvailableDates()
                if isViewingToday { reloadFromDisk() }
                if alreadyRunning {
                    notice = "已在生成"
                } else if succeeded {
                    setTransientNotice("已更新")
                } else {
                    notice = nil
                }
            }
            do {
                let result = try await runner.run(command)
                if result.isAlreadyRunning {
                    alreadyRunning = true
                } else {
                    succeeded = true
                }
            } catch let error as BriefctlError {
                switch error {
                case .failed(let exitCode, _) where exitCode == 75:
                    alreadyRunning = true
                default:
                    errorMessage = error.localizedDescription
                    status = .error
                }
            } catch {
                errorMessage = error.localizedDescription
                status = .error
            }
        }
    }

    /// Show a short-lived notice (e.g. 「已更新」) that auto-clears after a beat.
    private func setTransientNotice(_ message: String) {
        notice = message
        noticeClearTask?.cancel()
        noticeClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if notice == message { notice = nil }
        }
    }

    func doctor() {
        guard !isDoctorRunning else { return }
        isDoctorRunning = true
        notice = nil
        errorMessage = nil
        Task {
            defer { isDoctorRunning = false }
            do {
                let result = try await runner.run(.doctor)
                notice = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openFolder() {
        let directory = dayDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func computeStaleness(for brief: BriefDocument?) -> Bool {
        guard let generated = brief?.generatedAtDate else { return brief == nil }
        let threshold = brief?.stalenessHours ?? 36
        let hours = Date().timeIntervalSince(generated) / 3600
        return hours > threshold
    }
}
