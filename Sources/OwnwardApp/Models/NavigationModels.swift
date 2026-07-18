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

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case projectManagement
    case jobSearch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .projectManagement: "Project Management"
        case .jobSearch: "Job Search"
        }
    }
    var systemImage: String {
        switch self {
        case .projectManagement: "rectangle.3.group"
        case .jobSearch: "briefcase"
        }
    }

    var supportsProjectControls: Bool { self == .projectManagement }
}

enum JobTrackFilter: String, CaseIterable, Identifiable {
    case all
    case backup
    case canon
    case backupExtreme

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All Tracks"
        case .backup: "Backup"
        case .canon: "Canon"
        case .backupExtreme: "Backup Extreme"
        }
    }
    var track: JobSearchTrack? {
        switch self {
        case .all: nil
        case .backup: .backup
        case .canon: .canon
        case .backupExtreme: .backupExtreme
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
