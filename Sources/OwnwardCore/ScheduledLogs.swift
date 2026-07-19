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
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [ScheduledLogEntry] {
        let sorted = entries.sorted(by: newestFirst)
        let daily = sorted.filter { $0.kind == .dailyDayStarter }.prefix(4)

        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 4
        let currentWeek = weekKey(for: now, calendar: weekCalendar)
        let previousWeekDate = weekCalendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        let previousWeek = weekKey(for: previousWeekDate, calendar: weekCalendar)
        let weekly = sorted.filter {
            $0.kind == .weeklyCanadaRolesSearch
                && [currentWeek, previousWeek].contains(weekKey(for: $0.createdAt, calendar: weekCalendar))
        }

        return (daily + weekly).sorted(by: newestFirst)
    }

    private static func newestFirst(_ lhs: ScheduledLogEntry, _ rhs: ScheduledLogEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func weekKey(for date: Date, calendar: Calendar) -> WeekKey {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekKey(year: components.yearForWeekOfYear ?? 0, week: components.weekOfYear ?? 0)
    }
}

private struct WeekKey: Hashable {
    var year: Int
    var week: Int
}
