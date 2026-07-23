import Foundation

enum BriefctlCommand {
    case run
    case runFetchOnly
    case synth
    case doctor
    case todoView(date: String?, days: Int)
    case todoAdd(title: String, idempotencyKey: String)
    case todoStatus(id: String, status: WorkStatus, expectedVersion: Int)
    case todoNote(id: String, text: String, expectedVersion: Int, idempotencyKey: String)
    case todoUndo(eventID: String, expectedVersion: Int)

    var arguments: [String] {
        switch self {
        case .run: ["run"]
        case .runFetchOnly: ["run", "--skip-synth"]
        case .synth: ["synth"]
        case .doctor: ["doctor"]
        case let .todoView(date, days):
            if let date {
                ["todo", "view", "--date", date, "--days", String(days)]
            } else {
                ["todo", "view", "--days", String(days)]
            }
        case let .todoAdd(title, idempotencyKey):
            [
                "todo", "add", title,
                "--actor", "human",
                "--idempotency-key", idempotencyKey
            ]
        case let .todoStatus(id, status, expectedVersion):
            [
                "todo", "status", id, status.rawValue,
                "--actor", "human",
                "--expected-version", String(expectedVersion),
                "--idempotency-key", "ui:status:\(id):\(expectedVersion):\(status.rawValue)"
            ]
        case let .todoNote(id, text, expectedVersion, idempotencyKey):
            [
                "todo", "note", id, text,
                "--actor", "human",
                "--expected-version", String(expectedVersion),
                "--idempotency-key", idempotencyKey
            ]
        case let .todoUndo(eventID, expectedVersion):
            [
                "todo", "undo", eventID,
                "--actor", "human",
                "--reason", "从 Morning Brief 撤销",
                "--expected-version", String(expectedVersion),
                "--idempotency-key", "ui:undo:\(eventID)"
            ]
        }
    }
}

enum BriefctlError: LocalizedError {
    case executableNotFound
    case failed(exitCode: Int32, diagnostic: String)
    case invalidUTF8(stream: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Could not find briefctl. Set MORNINGBRIEF_BRIEFCTL or install briefctl on PATH."
        case let .failed(exitCode, diagnostic):
            if diagnostic.isEmpty {
                "briefctl exited with code \(exitCode)."
            } else {
                diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case let .invalidUTF8(stream):
            "briefctl returned non-UTF-8 \(stream)."
        }
    }
}

struct BriefctlResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isAlreadyRunning: Bool { exitCode == 75 }
}

struct BriefctlRunner: Sendable {
    /// Portable discovery: env → bootstrap marker → ~/.local/bin → PATH.
    static var candidates: [String] {
        var paths: [String] = []
        let home = NSHomeDirectory()
        let marker = "\(home)/Library/Application Support/MorningBrief/briefctl.path"
        if let pinned = try? String(contentsOfFile: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !pinned.isEmpty {
            paths.append(pinned)
        }
        paths.append("\(home)/.local/bin/briefctl")
        return paths
    }

    func resolveExecutable() -> String? {
        if let override = ProcessInfo.processInfo.environment["MORNINGBRIEF_BRIEFCTL"],
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for path in Self.candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return Self.which("briefctl")
    }

    func run(_ command: BriefctlCommand) async throws -> BriefctlResult {
        guard let executable = resolveExecutable() else {
            throw BriefctlError.executableNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.launch(executable: executable, arguments: command.arguments)
                    if result.exitCode == 0 || result.exitCode == 75 {
                        continuation.resume(returning: result)
                    } else {
                        let diagnostic = result.stderr.isEmpty ? result.stdout : result.stderr
                        continuation.resume(throwing: BriefctlError.failed(
                            exitCode: result.exitCode,
                            diagnostic: diagnostic
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func launch(executable: String, arguments: [String]) throws -> BriefctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("morningbrief-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: outputDirectory.path
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let stdoutURL = outputDirectory.appendingPathComponent("stdout")
        let stderrURL = outputDirectory.appendingPathComponent("stderr")
        _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
            process.waitUntilExit()
            try stdoutHandle.close()
            try stderrHandle.close()
        } catch {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            throw error
        }

        guard let stdout = String(
            data: try Data(contentsOf: stdoutURL),
            encoding: .utf8
        ) else {
            throw BriefctlError.invalidUTF8(stream: "stdout")
        }
        guard let stderr = String(
            data: try Data(contentsOf: stderrURL),
            encoding: .utf8
        ) else {
            throw BriefctlError.invalidUTF8(stream: "stderr")
        }

        return BriefctlResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = output, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}
