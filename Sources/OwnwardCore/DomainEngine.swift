import Foundation

public enum DomainError: Error, Equatable, LocalizedError {
    case boardNotFound
    case taskNotFound
    case miniTaskNotFound
    case targetNotFound
    case invalidReference
    case invalidBoardName
    case boardAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .boardNotFound: "Board not found."
        case .taskNotFound: "Task not found."
        case .miniTaskNotFound: "Mini-task not found."
        case .targetNotFound: "Completion target not found."
        case .invalidReference: "An item cannot reference itself."
        case .invalidBoardName: "A board name is required."
        case .boardAlreadyExists: "A board with that name already exists."
        }
    }
}

public enum TimelineEdge: String, Codable, Sendable {
    case start
    case end
}

public enum DomainEngine {
    @discardableResult
    public static func createBoard(named name: String, in snapshot: inout OwnwardSnapshot) throws -> Board {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw DomainError.invalidBoardName }
        guard !snapshot.boards.contains(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            throw DomainError.boardAlreadyExists
        }
        let board = Board(name: normalized)
        snapshot.boards.append(board)
        return board
    }

    public static func reorder(taskID: TaskID, before targetID: TaskID, in snapshot: inout OwnwardSnapshot) throws {
        guard let moving = snapshot.task(id: taskID), let target = snapshot.task(id: targetID) else {
            throw DomainError.taskNotFound
        }
        guard moving.boardID == target.boardID else { throw DomainError.taskNotFound }
        if moving.status != target.status { try move(taskID: taskID, to: target.status, in: &snapshot) }

        var lane = TaskOrganizer.sorted(
            snapshot.tasks.filter { $0.boardID == target.boardID && $0.status == target.status },
            by: .manual
        )
        lane.removeAll { $0.id == taskID }
        let insertion = lane.firstIndex { $0.id == targetID } ?? lane.endIndex
        guard let refreshed = snapshot.task(id: taskID) else { throw DomainError.taskNotFound }
        lane.insert(refreshed, at: insertion)
        for (order, task) in lane.enumerated() {
            if let index = snapshot.tasks.firstIndex(where: { $0.id == task.id }) {
                snapshot.tasks[index].manualOrder = order
                snapshot.tasks[index].updatedAt = Date()
            }
        }
    }

    public static func reorder(
        taskID: TaskID,
        before targetID: TaskID,
        inTeam team: String?,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        guard let target = snapshot.task(id: targetID) else { throw DomainError.taskNotFound }
        try move(taskID: taskID, to: target.status, team: team, in: &snapshot)
        try reorder(taskID: taskID, before: targetID, in: &snapshot)
    }

    public static func addReference(
        from source: CompletionTarget,
        to target: CompletionTarget,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        guard source != target else { throw DomainError.invalidReference }
        guard exists(source, in: snapshot), exists(target, in: snapshot) else {
            throw DomainError.targetNotFound
        }

        let sourceIndex = snapshot.referenceGroups.firstIndex { $0.members.contains(source) }
        let targetIndex = snapshot.referenceGroups.firstIndex { $0.members.contains(target) }

        switch (sourceIndex, targetIndex) {
        case (nil, nil):
            snapshot.referenceGroups.append(.init(members: [source, target]))
        case (let index?, nil):
            snapshot.referenceGroups[index].members.insert(target)
        case (nil, let index?):
            snapshot.referenceGroups[index].members.insert(source)
        case (let first?, let second?) where first != second:
            let members = snapshot.referenceGroups[first].members.union(snapshot.referenceGroups[second].members)
            let retained = min(first, second)
            let removed = max(first, second)
            snapshot.referenceGroups[retained].members = members
            snapshot.referenceGroups.remove(at: removed)
        default:
            break
        }

        let members = referenceMembers(for: source, in: snapshot)
        if members.contains(where: { isComplete($0, in: snapshot) }) {
            for member in members { try applyCompletion(true, to: member, in: &snapshot) }
        }
    }

    public static func setCompletion(
        of target: CompletionTarget,
        complete: Bool,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        guard exists(target, in: snapshot) else { throw DomainError.targetNotFound }
        for member in referenceMembers(for: target, in: snapshot) {
            try applyCompletion(complete, to: member, in: &snapshot)
        }
    }

    public static func move(taskID: TaskID, to status: TaskStatus, in snapshot: inout OwnwardSnapshot) throws {
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw DomainError.taskNotFound
        }
        if status == .done {
            try setCompletion(of: .task(taskID), complete: true, in: &snapshot)
            return
        }
        if snapshot.tasks[index].status == .done {
            try setCompletion(of: .task(taskID), complete: false, in: &snapshot)
        }
        guard let refreshed = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        snapshot.tasks[refreshed].status = status
        let destinationOrder = snapshot.tasks
            .filter { $0.boardID == snapshot.tasks[refreshed].boardID && $0.status == status && $0.id != taskID }
            .compactMap(\.manualOrder)
            .max()
            .map { $0 + 1 } ?? 0
        snapshot.tasks[refreshed].manualOrder = destinationOrder
        if status == .toDo || status == .inProgress || status == .paused {
            snapshot.tasks[refreshed].previousActiveStatus = status
        }
        snapshot.tasks[refreshed].updatedAt = Date()
    }

    public static func move(
        taskID: TaskID,
        to status: TaskStatus,
        team: String?,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        try move(taskID: taskID, to: status, in: &snapshot)
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw DomainError.taskNotFound
        }
        let normalizedTeam = team?.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.tasks[index].team = normalizedTeam?.isEmpty == true ? nil : normalizedTeam
        snapshot.tasks[index].updatedAt = Date()
    }

    public static func shiftSchedule(
        taskID: TaskID,
        byDays days: Int,
        calendar: Calendar = .current,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw DomainError.taskNotFound
        }
        guard days != 0 else { return }
        if let start = snapshot.tasks[index].deadlineStart {
            snapshot.tasks[index].deadlineStart = calendar.date(byAdding: .day, value: days, to: start)
        }
        if let end = snapshot.tasks[index].deadlineEnd {
            snapshot.tasks[index].deadlineEnd = calendar.date(byAdding: .day, value: days, to: end)
        }
        snapshot.tasks[index].updatedAt = Date()
    }

    public static func resizeSchedule(
        taskID: TaskID,
        edge: TimelineEdge,
        to date: Date,
        calendar: Calendar = .current,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else {
            throw DomainError.taskNotFound
        }
        let day = calendar.startOfDay(for: date)
        let existingStart = snapshot.tasks[index].deadlineStart
        let existingEnd = snapshot.tasks[index].deadlineEnd
        let currentStart = existingStart.map { calendar.startOfDay(for: $0) }
        let currentEnd = existingEnd.map { calendar.startOfDay(for: $0) }
        switch edge {
        case .start:
            snapshot.tasks[index].deadlineStart = if let existingEnd, let currentEnd, day > currentEnd {
                existingEnd
            } else {
                day
            }
        case .end:
            snapshot.tasks[index].deadlineEnd = if let existingStart, let currentStart, day < currentStart {
                existingStart
            } else {
                day
            }
        }
        snapshot.tasks[index].updatedAt = Date()
    }

    private static func referenceMembers(for target: CompletionTarget, in snapshot: OwnwardSnapshot) -> Set<CompletionTarget> {
        snapshot.referenceGroups.first { $0.members.contains(target) }?.members ?? [target]
    }

    private static func exists(_ target: CompletionTarget, in snapshot: OwnwardSnapshot) -> Bool {
        switch target {
        case .task(let id): snapshot.task(id: id) != nil
        case .miniTask(let id): snapshot.miniTask(id: id) != nil
        }
    }

    private static func isComplete(_ target: CompletionTarget, in snapshot: OwnwardSnapshot) -> Bool {
        switch target {
        case .task(let id): snapshot.task(id: id)?.status == .done
        case .miniTask(let id): snapshot.miniTask(id: id)?.isCompleted == true
        }
    }

    private static func applyCompletion(
        _ complete: Bool,
        to target: CompletionTarget,
        in snapshot: inout OwnwardSnapshot
    ) throws {
        switch target {
        case .task(let id):
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else {
                throw DomainError.taskNotFound
            }
            if complete {
                let current = snapshot.tasks[index].status
                if current != .done, current != .discarded {
                    snapshot.tasks[index].previousActiveStatus = current
                }
                snapshot.tasks[index].status = .done
            } else if snapshot.tasks[index].status == .done {
                snapshot.tasks[index].status = snapshot.tasks[index].previousActiveStatus ?? .toDo
            }
            snapshot.tasks[index].updatedAt = Date()

        case .miniTask(let id):
            for taskIndex in snapshot.tasks.indices {
                guard let miniIndex = snapshot.tasks[taskIndex].miniTasks.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                snapshot.tasks[taskIndex].miniTasks[miniIndex].isCompleted = complete
                snapshot.tasks[taskIndex].updatedAt = Date()
                return
            }
            throw DomainError.miniTaskNotFound
        }
    }
}
