import Foundation

final class BriefWatcher {
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var watchedDirectory: URL?
    private var lastBriefSignature: FileSignature?
    private var lastRunSignature: FileSignature?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func watch(directory: URL) {
        stop()
        watchedDirectory = directory
        lastBriefSignature = nil
        lastRunSignature = nil

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fd = open(directory.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.emitIfChanged(force: true)
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            directorySource = source
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.emitIfChanged(force: false)
        }

        emitIfChanged(force: true)
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        pollTimer?.invalidate()
        pollTimer = nil
        watchedDirectory = nil
        lastBriefSignature = nil
        lastRunSignature = nil
    }

    private func emitIfChanged(force: Bool) {
        guard let directory = watchedDirectory else { return }

        let briefSignature = FileSignature(url: BriefPaths.briefJSON(in: directory))
        let runSignature = FileSignature(url: BriefPaths.runJSON(in: directory))

        let changed = force
            || briefSignature != lastBriefSignature
            || runSignature != lastRunSignature

        guard changed else { return }

        lastBriefSignature = briefSignature
        lastRunSignature = runSignature
        onChange()
    }
}

private struct FileSignature: Equatable {
    let exists: Bool
    let modificationDate: Date?
    let size: Int

    init(url: URL) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            exists = true
            modificationDate = attributes[.modificationDate] as? Date
            size = attributes[.size] as? Int ?? 0
        } else {
            exists = false
            modificationDate = nil
            size = 0
        }
    }
}
