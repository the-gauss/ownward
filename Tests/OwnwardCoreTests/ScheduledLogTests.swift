import Foundation
import Testing
@testable import OwnwardCore

@Suite("Scheduled log retention")
struct ScheduledLogTests {
    @Test("logs retain only the newest run for each kind")
    func retainsNewestRunForEachKind() {
        let entries = [
            ScheduledLogEntry(kind: .dailyDayStarter, markdown: "Yesterday", createdAt: date("2026-07-19T08:00:00Z")),
            ScheduledLogEntry(kind: .weeklyCanadaRolesSearch, markdown: "Last week", createdAt: date("2026-07-14T08:00:00Z")),
            ScheduledLogEntry(kind: .weeklyCanadaRolesSearch, markdown: "This week", createdAt: date("2026-07-20T06:00:00Z")),
            ScheduledLogEntry(kind: .dailyDayStarter, markdown: "Today", createdAt: date("2026-07-20T08:00:00Z")),
        ]

        let retained = ScheduledLogRetention.prune(entries)

        #expect(retained.map(\.markdown) == ["Today", "This week"])
    }

    @Test("adding a run replaces only older runs of the same kind")
    func addingReplacesOnlySameKind() {
        let existing = [
            ScheduledLogEntry(kind: .dailyDayStarter, markdown: "Yesterday", createdAt: date("2026-07-19T08:00:00Z")),
            ScheduledLogEntry(kind: .weeklyCanadaRolesSearch, markdown: "This week", createdAt: date("2026-07-20T06:00:00Z")),
        ]
        let today = ScheduledLogEntry(
            kind: .dailyDayStarter,
            markdown: "Today",
            createdAt: date("2026-07-20T08:00:00Z")
        )

        let retained = ScheduledLogRetention.adding(today, to: existing)

        #expect(retained.map(\.markdown) == ["Today", "This week"])
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
