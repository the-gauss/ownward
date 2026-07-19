import Foundation

public enum ScheduledLogKind: String, Codable, CaseIterable, Sendable {
    case dailyDayStarter = "daily_day_starter"
    case weeklyCanadaRolesSearch = "weekly_canada_roles_search"

    public var title: String {
        switch self {
        case .dailyDayStarter: "Daily Log"
        case .weeklyCanadaRolesSearch: "Weekly Log"
        }
    }
}

public struct ScheduledLogEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ScheduledLogKind
    public var markdown: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ScheduledLogKind,
        markdown: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.markdown = markdown
        self.createdAt = createdAt
    }
}

public enum ScheduledLogRetention {
    public static func adding(
        _ entry: ScheduledLogEntry,
        to existing: [ScheduledLogEntry],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledLogEntry] {
        prune(existing + [entry], now: now, calendar: calendar)
    }

    public static func prune(
        _ entries: [ScheduledLogEntry],
        now _: Date = Date(),
        calendar _: Calendar = .autoupdatingCurrent
    ) -> [ScheduledLogEntry] {
        let sorted = entries.sorted(by: newestFirst)
        return ScheduledLogKind.allCases.compactMap { kind in
            sorted.first { $0.kind == kind }
        }
        .sorted(by: newestFirst)
    }

    private static func newestFirst(_ lhs: ScheduledLogEntry, _ rhs: ScheduledLogEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
