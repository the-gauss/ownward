import Foundation

public enum TaskSort: String, Codable, CaseIterable, Sendable {
    case manual
    case deadline
    case checklistProgress = "checklist_progress"

    public var title: String {
        switch self {
        case .manual: "Default Order"
        case .deadline: "Deadline"
        case .checklistProgress: "Checklist Progress"
        }
    }
}

public enum TaskGrouping: String, Codable, CaseIterable, Sendable {
    case none
    case status
    case team

    public var title: String {
        switch self {
        case .none: "None"
        case .status: "Status"
        case .team: "Team"
        }
    }
}

public enum TaskDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case overdue
    case dueToday = "due_today"
    case scheduled
    case unscheduled

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "Any Date"
        case .overdue: "Overdue"
        case .dueToday: "Due Today"
        case .scheduled: "Has Dates"
        case .unscheduled: "No Dates"
        }
    }
}

public enum TaskTeamFilter: Equatable, Sendable {
    case all
    case named(String)
    case unassigned

    public var title: String {
        switch self {
        case .all: "All Teams"
        case .named(let name): name
        case .unassigned: "No Team"
        }
    }
}

public struct TaskFilter: Equatable, Sendable {
    public var status: TaskStatus?
    public var team: TaskTeamFilter
    public var date: TaskDateFilter

    public init(
        status: TaskStatus? = nil,
        team: TaskTeamFilter = .all,
        date: TaskDateFilter = .all
    ) {
        self.status = status
        self.team = team
        self.date = date
    }

    public var activeCriterionCount: Int {
        (status == nil ? 0 : 1) + (team == .all ? 0 : 1) + (date == .all ? 0 : 1)
    }

    public var isActive: Bool { activeCriterionCount > 0 }
}

public struct TaskGroup: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var tasks: [TaskItem]

    public init(title: String, tasks: [TaskItem]) {
        self.title = title
        self.tasks = tasks
    }
}

public struct TeamSwimlane: Identifiable, Equatable, Sendable {
    public var id: String { team }
    public let team: String
    private let members: [TaskItem]

    public init(team: String, tasks: [TaskItem]) {
        self.team = team
        members = tasks
    }

    public func tasks(in status: TaskStatus) -> [TaskItem] {
        members.filter { $0.status == status }
    }

    public var count: Int { members.count }
}

public struct ChecklistCategoryGroup: Identifiable, Equatable, Sendable {
    public var id: String { "\(category ?? "__uncategorized")-\(items.first?.order ?? -1)" }
    public var category: String?
    public var items: [MiniTask]

    public init(category: String?, items: [MiniTask]) {
        self.category = category
        self.items = items
    }
}

public enum ChecklistOrganizer {
    /// Preserves the source order while collecting adjacent checklist items under
    /// their imported Markdown heading. The explicit index check is important:
    /// `nil == nil` is true, even when the destination array is still empty.
    public static func grouped<S: Sequence>(_ items: S) -> [ChecklistCategoryGroup]
    where S.Element == MiniTask {
        items.reduce(into: []) { groups, mini in
            if let lastIndex = groups.indices.last,
               groups[lastIndex].category == mini.category {
                groups[lastIndex].items.append(mini)
            } else {
                groups.append(ChecklistCategoryGroup(category: mini.category, items: [mini]))
            }
        }
    }
}

public enum TaskOrganizer {
    public static func filtered(
        _ tasks: [TaskItem],
        by filter: TaskFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        return tasks.filter { task in
            guard filter.status == nil || task.status == filter.status else { return false }
            switch filter.team {
            case .all:
                break
            case .named(let expected):
                guard task.team?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(expected.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame else {
                    return false
                }
            case .unassigned:
                guard task.team?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                    return false
                }
            }

            let dueDate = task.deadlineEnd ?? task.deadlineStart
            switch filter.date {
            case .all:
                return true
            case .overdue:
                guard task.status != .done, task.status != .discarded, let dueDate else { return false }
                return calendar.startOfDay(for: dueDate) < today
            case .dueToday:
                guard let dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: today)
            case .scheduled:
                return dueDate != nil
            case .unscheduled:
                return dueDate == nil
            }
        }
    }

    public static func sorted(_ tasks: [TaskItem], by sort: TaskSort) -> [TaskItem] {
        tasks.enumerated().sorted { left, right in
            let lhs = left.element
            let rhs = right.element
            switch sort {
            case .manual:
                let leftOrder = lhs.manualOrder ?? left.offset
                let rightOrder = rhs.manualOrder ?? right.offset
                return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
            case .deadline:
                switch (lhs.deadlineEnd ?? lhs.deadlineStart, rhs.deadlineEnd ?? rhs.deadlineStart) {
                case (let l?, let r?): return l == r ? stableTie(lhs, rhs) : l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return stableTie(lhs, rhs)
                }
            case .checklistProgress:
                return lhs.checklistProgress == rhs.checklistProgress
                    ? stableTie(lhs, rhs)
                    : lhs.checklistProgress < rhs.checklistProgress
            }
        }.map(\.element)
    }

    public static func grouped(_ tasks: [TaskItem], by grouping: TaskGrouping) -> [TaskGroup] {
        switch grouping {
        case .none:
            return [TaskGroup(title: "All Tasks", tasks: tasks)]
        case .status:
            return TaskStatus.allCases.compactMap { status in
                let members = tasks.filter { $0.status == status }
                return members.isEmpty ? nil : TaskGroup(title: status.title, tasks: members)
            }
        case .team:
            let dictionary = Dictionary(grouping: tasks) { $0.team?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "No Team" }
            return dictionary.keys.sorted { left, right in
                if left == "No Team" { return false }
                if right == "No Team" { return true }
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }.map { TaskGroup(title: $0, tasks: dictionary[$0] ?? []) }
        }
    }

    public static func teamSwimlanes(_ tasks: [TaskItem], sort: TaskSort) -> [TeamSwimlane] {
        grouped(tasks, by: .team).map { group in
            TeamSwimlane(team: group.title, tasks: sorted(group.tasks, by: sort))
        }
    }

    private static func stableTie(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let left = lhs.manualOrder ?? .max
        let right = rhs.manualOrder ?? .max
        return left == right ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending : left < right
    }
}

public struct TimelineScale: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let calendar: Calendar

    public init(start: Date, end: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let normalizedStart = calendar.startOfDay(for: min(start, end))
        let normalizedEnd = calendar.startOfDay(for: max(start, end))
        self.start = normalizedStart
        self.end = normalizedEnd
    }

    public var totalDays: Int { spanDays(from: start, through: end) }

    public func dayOffset(for date: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
    }

    public func spanDays(from startDate: Date, through endDate: Date) -> Int {
        let first = calendar.startOfDay(for: min(startDate, endDate))
        let last = calendar.startOfDay(for: max(startDate, endDate))
        return (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
    }
}

public enum TimelineDragOperation: Equatable, Sendable {
    case move
    case resizeStart
    case resizeEnd
}

public enum TimelineDragMath {
    public static func operation(
        at horizontalPosition: Double,
        barWidth: Double,
        handleWidth: Double
    ) -> TimelineDragOperation {
        let safeWidth = max(0, barWidth)
        let safeHandle = min(max(0, handleWidth), safeWidth / 2)
        if horizontalPosition <= safeHandle { return .resizeStart }
        if horizontalPosition >= safeWidth - safeHandle { return .resizeEnd }
        return .move
    }

    public static func dayDelta(
        translation: Double,
        dayWidth: Double,
        operation: TimelineDragOperation,
        spanDays: Int
    ) -> Int {
        guard dayWidth > 0 else { return 0 }
        let raw = Int((translation / dayWidth).rounded())
        let maximumEdgeDelta = max(0, spanDays - 1)
        switch operation {
        case .move: return raw
        case .resizeStart: return min(raw, maximumEdgeDelta)
        case .resizeEnd: return max(raw, -maximumEdgeDelta)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
