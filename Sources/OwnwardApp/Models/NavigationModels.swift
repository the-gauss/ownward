import Foundation
import OwnwardCore

enum MainViewMode: String, CaseIterable, Identifiable {
    case kanban, table, timeline
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .kanban: "rectangle.split.3x1"
        case .table: "list.bullet"
        case .timeline: "calendar.day.timeline.left"
        }
    }
}

enum SavedView: String, CaseIterable, Identifiable {
    case today, upcoming, paused, discarded
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .upcoming: "clock"
        case .paused: "pause.circle"
        case .discarded: "trash"
        }
    }
}

enum SidebarSelection: Hashable {
    case board(BoardID)
    case saved(SavedView)
}
