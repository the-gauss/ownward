import Foundation
import OwnwardCore

public protocol ScheduledLogNotifier: Sendable {
    func notify(of entry: ScheduledLogEntry) async
}

public struct NoopScheduledLogNotifier: ScheduledLogNotifier {
    public init() {}
    public func notify(of entry: ScheduledLogEntry) async {}
}
