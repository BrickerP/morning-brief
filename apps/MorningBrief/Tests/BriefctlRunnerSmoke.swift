import Foundation

@main
struct BriefctlRunnerSmoke {
    static func main() async throws {
        let created = WorkEvent(
            sequence: 1,
            eventId: "created",
            itemId: "clock",
            kind: "created",
            actor: "human",
            occurredAt: "2026-07-23T10:00:00.000000Z",
            payload: ["title": .string("时钟回拨")],
            reason: nil,
            evidence: [],
            idempotencyKey: nil,
            targetEventId: nil
        )
        let status = WorkEvent(
            sequence: 2,
            eventId: "status",
            itemId: "clock",
            kind: "status_changed",
            actor: "agent",
            occurredAt: "2026-07-23T09:00:00.000000Z",
            payload: ["status": .string("in_progress")],
            reason: "系统时钟校准",
            evidence: [],
            idempotencyKey: nil,
            targetEventId: nil
        )
        let item = WorkItem(
            id: "clock",
            title: "时钟回拨",
            detail: "",
            status: .inProgress,
            createdAt: created.occurredAt,
            updatedAt: status.occurredAt,
            version: 2,
            terminalDate: nil,
            events: [created, status]
        )
        let document = WorkDocument(
            schemaVersion: 1,
            date: "2026-07-23",
            generatedAt: "2026-07-23T11:00:00.000000Z",
            readOnly: false,
            items: [item],
            recentHistory: [],
            latestAgentEvent: status
        )
        guard document.latestReversibleEvent?.eventId == status.eventId else {
            fatalError("latest reversible event must follow commit sequence")
        }

        let editArguments = BriefctlCommand.todoEdit(
            id: "clock",
            title: "校准系统时钟",
            detail: "检查 NTP 与时区配置",
            expectedVersion: 2,
            idempotencyKey: "ui:edit:clock:2"
        ).arguments
        guard editArguments == [
            "todo", "edit", "clock",
            "--title", "校准系统时钟",
            "--detail", "检查 NTP 与时区配置",
            "--actor", "human",
            "--expected-version", "2",
            "--idempotency-key", "ui:edit:clock:2"
        ] else {
            fatalError("todo edit arguments are incomplete: \(editArguments)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("morningbrief-runner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("fake-briefctl")
        let script = """
        #!/bin/zsh
        if [[ "$1" == "doctor" ]]; then
          print '{"error":{"message":"expected-version conflict"}}'
          exit 2
        fi
        /usr/bin/python3 -c 'import sys; sys.stdout.write("x" * 1100000)'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        setenv("MORNINGBRIEF_BRIEFCTL", executable.path, 1)

        let large = try await BriefctlRunner().run(
            .todoAdd(title: "large-output", idempotencyKey: "runner-smoke")
        )
        guard large.stdout.count > 1_000_000 else {
            fatalError("large stdout was truncated")
        }

        do {
            _ = try await BriefctlRunner().run(.doctor)
            fatalError("doctor should fail")
        } catch {
            guard error.localizedDescription.contains("expected-version conflict") else {
                fatalError("stdout diagnostic was not surfaced: \(error)")
            }
        }

        print("BriefctlRunner smoke passed")
    }
}
