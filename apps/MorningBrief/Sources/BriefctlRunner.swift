import Foundation

enum BriefctlCommand {
    case run
    case runFetchOnly
    case synth
    case doctor

    var arguments: [String] {
        switch self {
        case .run: ["run"]
        case .runFetchOnly: ["run", "--skip-synth"]
        case .synth: ["synth"]
        case .doctor: ["doctor"]
        }
    }
}

enum BriefctlError: LocalizedError {
    case executableNotFound
    case failed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Could not find briefctl. Set MORNINGBRIEF_BRIEFCTL or install briefctl on PATH."
        case let .failed(exitCode, stderr):
            if stderr.isEmpty {
                "briefctl exited with code \(exitCode)."
            } else {
                stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
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
                        continuation.resume(throwing: BriefctlError.failed(
                            exitCode: result.exitCode,
                            stderr: result.stderr
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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

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
