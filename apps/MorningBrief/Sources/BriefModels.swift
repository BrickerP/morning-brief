import Foundation

enum BriefStatus: String, Codable, CaseIterable {
    case idle
    case fetching
    case synthesizing
    case running
    case ready
    case degraded
    case failed
    case error
    case locked

    var iconName: String {
        switch self {
        case .idle: "sun.horizon"
        case .fetching, .synthesizing, .running: "arrow.triangle.2.circlepath"
        case .ready: "newspaper"
        case .degraded: "exclamationmark.triangle"
        case .locked: "hourglass"
        case .failed, .error: "xmark.circle"
        }
    }

    init(runStatus raw: String) {
        switch raw.lowercased() {
        case "fetching": self = .fetching
        case "synthesizing": self = .synthesizing
        case "ready": self = .ready
        case "degraded": self = .degraded
        case "failed": self = .failed
        case "locked": self = .locked
        case "idle": self = .idle
        default: self = .idle
        }
    }
}

enum SectionStatus: String, Codable {
    case ok, empty, failed, partial, synthesized, unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased() ?? ""
        self = SectionStatus(rawValue: raw) ?? .unknown
    }
}

struct BriefSection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let bodyMd: String
    let sourceIds: [String]
    let status: SectionStatus

    enum CodingKeys: String, CodingKey {
        case id, title, kind
        case bodyMd = "body_md"
        case sourceIds = "source_ids"
        case status
    }

    var body: String { bodyMd }

    /// True when the section carries something worth reading (non-empty body and
    /// not an empty/failed placeholder). Drives hero vs. empty-state decisions.
    var hasContent: Bool {
        guard !bodyMd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch status {
        case .ok, .partial, .synthesized: return true
        case .empty, .failed, .unknown: return false
        }
    }
}

/// One must-read row inside the hero. Optional `sectionId` links to a full
/// section for in-panel expansion; optional `url` opens externally.
struct HeroMustRead: Codable, Hashable {
    let title: String
    let summary: String?
    let sectionId: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case title, summary
        case sectionId = "section_id"
        case url
    }
}

/// The above-the-fold conclusion: a headline plus up to three must-reads.
struct BriefHero: Codable, Hashable {
    let headline: String
    let mustReads: [HeroMustRead]

    enum CodingKeys: String, CodingKey {
        case headline
        case mustReads = "must_reads"
    }

    var hasContent: Bool {
        !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mustReads.isEmpty
    }
}

struct BriefSourceChip: Identifiable, Hashable {
    let id: String
    let name: String
    let status: SectionStatus
}

struct BriefDocument: Codable {
    let date: String
    let generatedAt: String
    let status: String
    let sections: [BriefSection]
    let hero: BriefHero?
    let meta: [String: FlexibleJSON]?

    enum CodingKeys: String, CodingKey {
        case date
        case generatedAt = "generated_at"
        case status
        case sections
        case hero
        case meta
    }

    /// Sections that actually carry readable content.
    var readableSections: [BriefSection] {
        sections.filter(\.hasContent)
    }

    /// True when there is something to show above the empty-state one-liner:
    /// a populated hero or at least one readable section.
    var hasReadableContent: Bool {
        (hero?.hasContent ?? false) || !readableSections.isEmpty
    }

    var generatedAtDate: Date? {
        BriefDateParser.iso8601.date(from: generatedAt)
            ?? BriefDateParser.iso8601Fractional.date(from: generatedAt)
    }

    /// Staleness threshold in hours from pipeline meta, if present.
    var stalenessHours: Double? {
        if case .number(let v)? = meta?["staleness_hours"] { return v }
        return nil
    }

    /// Synthesis mode badge from pipeline meta (agent/degraded/skipped/cached/schema_fallback/none).
    var synthBadge: String? {
        if case .string(let v)? = meta?["synth"] { return v }
        return nil
    }
}

struct RunDocument: Codable {
    let status: String?
    let sources: [String: RunSourceStatus]?
    let errors: [String]?

    var briefStatus: BriefStatus {
        BriefStatus(runStatus: status ?? "idle")
    }

    /// Chips derived from fetch-time source statuses in run.json (id as name; run.json has no title).
    var sourceChips: [BriefSourceChip] {
        guard let sources else { return [] }
        return sources.keys.sorted().map { id in
            let raw = (sources[id]?.status ?? "").lowercased()
            return BriefSourceChip(id: id, name: id, status: SectionStatus(rawValue: raw) ?? .unknown)
        }
    }
}

struct RunSourceStatus: Codable {
    let status: String?
}

/// Accept arbitrary JSON values in meta without failing decode.
enum FlexibleJSON: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: FlexibleJSON])
    case array([FlexibleJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([String: FlexibleJSON].self) { self = .object(v); return }
        if let v = try? container.decode([FlexibleJSON].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

enum BriefDateParser {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum BriefPaths {
    static let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MorningBrief/briefs", isDirectory: true)

    /// Timezone used to derive `yyyy-MM-dd` day-folder keys.
    /// MUST stay aligned with briefctl's default `config.timezone` (Python `AppConfig.timezone`),
    /// otherwise the app and the CLI would disagree on which folder is "today".
    static let dayTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = dayTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    /// `yyyy-MM-dd` day key for the given date in `dayTimeZone`.
    static func dayString(for date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    /// Today's day key (in `dayTimeZone`).
    static func todayDateString() -> String {
        dayString(for: Date())
    }

    static func dayDirectory(for date: Date = Date()) -> URL {
        appSupport.appendingPathComponent(dayString(for: date), isDirectory: true)
    }

    static func dayDirectory(forDateString dateString: String) -> URL {
        appSupport.appendingPathComponent(dateString, isDirectory: true)
    }

    /// True if `value` is a valid `yyyy-MM-dd` day key.
    static func isDayString(_ value: String) -> Bool {
        value.count == 10 && dayFormatter.date(from: value) != nil
    }

    /// Day keys (`yyyy-MM-dd`) that have a folder under `appSupport`, sorted ascending.
    static func availableDates() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.compactMap { url -> String? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            return isDir && isDayString(name) ? name : nil
        }.sorted()
    }

    static func briefJSON(in directory: URL) -> URL {
        directory.appendingPathComponent("brief.json")
    }

    static func runJSON(in directory: URL) -> URL {
        directory.appendingPathComponent("run.json")
    }
}
