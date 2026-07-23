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

        let followUp = WorkEvent(
            sequence: 3,
            eventId: "follow-up",
            itemId: "clock",
            kind: "progress_added",
            actor: "human",
            occurredAt: "2026-07-23T10:30:00.000000Z",
            payload: ["text": .string("继续验证生产环境支付链路")],
            reason: nil,
            evidence: [],
            idempotencyKey: nil,
            targetEventId: nil
        )
        let selectableItem = WorkItem(
            id: item.id,
            title: "今天测试支付回归",
            detail: "",
            status: item.status,
            createdAt: item.createdAt,
            updatedAt: followUp.occurredAt,
            version: 3,
            terminalDate: nil,
            events: [created, status, followUp]
        )
        let transcript = selectableItem.selectionTranscript { event in
            event.eventId == followUp.eventId ? "10:30" : "10:00"
        }
        guard transcript.hasPrefix("今天测试支付回归\n\n"),
              transcript.contains("Agent · 10:00\n状态：待处理 → 进行中"),
              transcript.contains("你 · 10:30\n继续验证生产环境支付链路") else {
            fatalError("selection transcript must keep title and follow-ups in one string: \(transcript)")
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

        // Cancellation: a long-running briefctl is terminated by Task cancel and
        // surfaces CancellationError (not a failed exit-code banner), promptly.
        let sleeper = directory.appendingPathComponent("sleep-briefctl")
        let sleepScript = """
        #!/bin/zsh
        /usr/bin/python3 -c 'import time; time.sleep(30)'
        """
        try sleepScript.write(to: sleeper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sleeper.path
        )
        setenv("MORNINGBRIEF_BRIEFCTL", sleeper.path, 1)

        let cancelStart = Date()
        let cancelTask = Task { () -> BriefctlResult in
            try await BriefctlRunner().run(.todoView(date: nil, days: 7))
        }
        // Let the subprocess actually start before cancelling.
        try await Task.sleep(nanoseconds: 500_000_000)
        cancelTask.cancel()
        do {
            _ = try await cancelTask.value
            fatalError("cancelled run should throw")
        } catch is CancellationError {
            // expected
        } catch {
            fatalError("cancelled run should throw CancellationError, got: \(error)")
        }
        guard Date().timeIntervalSince(cancelStart) < 10 else {
            fatalError("cancellation did not promptly terminate the 30s sleep")
        }

        print("BriefctlRunner smoke passed")
    }
}
