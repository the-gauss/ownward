import Foundation
import Testing
@testable import OwnwardCore

@Suite("Scheduled log retention")
struct ScheduledLogTests {
    @Test("daily logs retain only the four newest entries")
    func retainsFourDailyEntries() {
        let calendar = utcISOCalendar
        let now = date("2026-07-19T12:00:00Z")
        let entries = (1...5).map { offset in
            ScheduledLogEntry(
                kind: .dailyDayStarter,
                markdown: "Daily \(offset)",
                createdAt: date("2026-07-1\(offset)T08:00:00Z")
            )
        }

        let retained = ScheduledLogRetention.prune(entries, now: now, calendar: calendar)

        #expect(retained.map(\.markdown) == ["Daily 5", "Daily 4", "Daily 3", "Daily 2"])
    }

    @Test("weekly logs retain the current and preceding ISO weeks only")
    func retainsCurrentAndPreviousWeeks() {
        let calendar = utcISOCalendar
        let now = date("2026-07-19T12:00:00Z")
        let entries = [
            ScheduledLogEntry(kind: .weeklyCanadaRolesSearch, markdown: "Current", createdAt: date("2026-07-14T08:00:00Z")),
            ScheduledLogEntry(kind: .weeklyCanadaRolesSearch, markdown: "Previous", createdAt: date("2026-07-07T08:00:00Z")),
            ScheduledLogEntry(kind: .weeklyCanadaRolesSearch, markdown: "Expired", createdAt: date("2026-06-30T08:00:00Z")),
        ]

        let retained = ScheduledLogRetention.prune(entries, now: now, calendar: calendar)

        #expect(retained.map(\.markdown) == ["Current", "Previous"])
    }

    private var utcISOCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
