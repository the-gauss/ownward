import Foundation
import OwnwardCore
import OwnwardServices
import UserNotifications

final class OwnwardNotificationScheduler: @unchecked Sendable, ScheduledLogNotifier {
    static func requestAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    func notify(of entry: ScheduledLogEntry) async {
        let content = UNMutableNotificationContent()
        content.title = entry.kind.title
        content.body = entry.kind == .dailyDayStarter
            ? "Daily Day Starter is ready. Open Ownward to review it."
            : "Weekly Canada Roles Search is ready. Open Ownward to review it."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "scheduled-log-\(entry.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
