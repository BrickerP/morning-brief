import Foundation

/// Dependency boundary around `BriefctlRunner` for WorkFeature effects.
struct BriefctlClient: Sendable {
    var run: @Sendable (BriefctlCommand) async throws -> BriefctlResult

    static let live = BriefctlClient(
        run: { command in
            try await BriefctlRunner().run(command)
        }
    )
}

extension BriefctlClient {
    func todoView(date: String?, days: Int = 7) async throws -> WorkDocument {
        let result = try await run(.todoView(date: date, days: days))
        return try JSONDecoder().decode(WorkDocument.self, from: Data(result.stdout.utf8))
    }

    func mutate(_ command: BriefctlCommand) async throws {
        _ = try await run(command)
    }
}
