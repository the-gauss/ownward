import Foundation
import Observation
import OwnwardCore
import OwnwardServices

@MainActor
@Observable
final class AppModel {
    private let repository: WorkspaceRepository
    private let apiServer: LocalAPIServer
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    var snapshot: OwnwardSnapshot
    var sidebarSelection: SidebarSelection
    var selectedTaskID: TaskID?
    var viewMode: MainViewMode = .kanban
    var searchText = ""
    var apiError: String?
    var kanbanGrouping: TaskGrouping = .none
    var kanbanSort: TaskSort = .manual
    var tableGrouping: TaskGrouping = .status
    var tableSort: TaskSort = .deadline
    var timelineGrouping: TaskGrouping = .status
    var tableTaskColumnWidth: Double {
        didSet {
            tableTaskColumnWidth = TableTaskColumnWidth.clamped(tableTaskColumnWidth)
            UserDefaults.standard.set(tableTaskColumnWidth, forKey: "tableTaskColumnWidth")
        }
    }
    var themeChoice: AppThemeChoice {
        didSet { UserDefaults.standard.set(themeChoice.rawValue, forKey: "appearanceTheme") }
    }
    var zoomScale: Double {
        didSet { UserDefaults.standard.set(zoomScale, forKey: "zoomScale") }
    }

    init(repository: WorkspaceRepository, apiServer: LocalAPIServer, initialSnapshot: OwnwardSnapshot) {
        self.repository = repository
        self.apiServer = apiServer
        snapshot = initialSnapshot
        sidebarSelection = .board(initialSnapshot.boards.first?.id ?? BoardID())
        themeChoice = UserDefaults.standard.string(forKey: "appearanceTheme")
            .flatMap(AppThemeChoice.init(rawValue:)) ?? .system
        let savedZoom = UserDefaults.standard.double(forKey: "zoomScale")
        zoomScale = savedZoom == 0 ? 1 : min(ZoomLevel.maximum, max(ZoomLevel.minimum, savedZoom))
        let savedTaskWidth = UserDefaults.standard.double(forKey: "tableTaskColumnWidth")
        tableTaskColumnWidth = savedTaskWidth == 0
            ? TableTaskColumnWidth.defaultValue
            : TableTaskColumnWidth.clamped(savedTaskWidth)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        do { try apiServer.start() }
        catch { apiError = "Local API could not start: \(error.localizedDescription)" }
        observationTask = Task { [weak self, repository] in
            for await update in await repository.changes() {
                guard !Task.isCancelled else { break }
                self?.snapshot = update
            }
        }
    }

    var selectedBoard: Board? {
        guard case .board(let id) = sidebarSelection else { return snapshot.boards.first }
        return snapshot.boards.first { $0.id == id }
    }

    var selectedTask: TaskItem? {
        selectedTaskID.flatMap(snapshot.task(id:))
    }

    var visibleTasks: [TaskItem] {
        let scoped: [TaskItem]
        switch sidebarSelection {
        case .board(let id):
            scoped = snapshot.tasks.filter { $0.boardID == id && TaskStatus.boardColumns.contains($0.status) }
        case .saved(.today):
            let calendar = Calendar.current
            scoped = snapshot.tasks.filter { task in
                guard let date = task.deadlineStart ?? task.deadlineEnd else { return false }
                return calendar.isDateInToday(date) && task.status != .done && task.status != .discarded
            }
        case .saved(.upcoming):
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 14, to: start)!
            scoped = snapshot.tasks.filter { task in
                guard let date = task.deadlineEnd ?? task.deadlineStart else { return false }
                return date >= start && date <= end && task.status != .done && task.status != .discarded
            }
        case .saved(.paused): scoped = snapshot.tasks.filter { $0.status == .paused }
        case .saved(.discarded): scoped = snapshot.tasks.filter { $0.status == .discarded }
        }
        guard !searchText.isEmpty else { return scoped }
        return scoped.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.notesMarkdown.localizedCaseInsensitiveContains(searchText) }
    }

    func createTask(in status: TaskStatus = .toDo) {
        guard let board = selectedBoard else { return }
        let nextOrder = snapshot.tasks
            .filter { $0.boardID == board.id && $0.status == status }
            .compactMap(\.manualOrder).max().map { $0 + 1 } ?? 0
        let task = TaskItem(boardID: board.id, title: "New Task", status: status, team: board.teams.first, manualOrder: nextOrder)
        Task {
            _ = try? await repository.mutate { $0.tasks.append(task) }
            selectedTaskID = task.id
        }
    }

    func createBoard(named name: String) {
        Task {
            do {
                let updated = try await repository.mutate { _ = try DomainEngine.createBoard(named: name, in: &$0) }
                if let board = updated.boards.first(where: { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
                    sidebarSelection = .board(board.id)
                }
            } catch {
                apiError = error.localizedDescription
            }
        }
    }

    func move(_ taskID: TaskID, to status: TaskStatus) {
        Task { _ = try? await repository.mutate { try DomainEngine.move(taskID: taskID, to: status, in: &$0) } }
    }

    func move(_ taskID: TaskID, to status: TaskStatus, team: String?) {
        Task { _ = try? await repository.mutate { try DomainEngine.move(taskID: taskID, to: status, team: team, in: &$0) } }
    }

    func reorder(_ taskID: TaskID, before targetID: TaskID) {
        Task { _ = try? await repository.mutate { try DomainEngine.reorder(taskID: taskID, before: targetID, in: &$0) } }
    }

    func reorder(_ taskID: TaskID, before targetID: TaskID, team: String?) {
        Task { _ = try? await repository.mutate { try DomainEngine.reorder(taskID: taskID, before: targetID, inTeam: team, in: &$0) } }
    }

    func zoomIn() { zoomScale = ZoomLevel.increased(from: zoomScale) }
    func zoomOut() { zoomScale = ZoomLevel.decreased(from: zoomScale) }
    func resetZoom() { zoomScale = 1 }
    func resetTableTaskColumnWidth() { tableTaskColumnWidth = TableTaskColumnWidth.defaultValue }

    func shiftTaskDates(_ taskID: TaskID, byDays days: Int) {
        guard days != 0 else { return }
        Task { _ = try? await repository.mutate { try DomainEngine.shiftSchedule(taskID: taskID, byDays: days, in: &$0) } }
    }

    func resizeTaskDates(_ taskID: TaskID, edge: TimelineEdge, to date: Date) {
        Task { _ = try? await repository.mutate { try DomainEngine.resizeSchedule(taskID: taskID, edge: edge, to: date, in: &$0) } }
    }

    func toggleTask(_ task: TaskItem) {
        Task { _ = try? await repository.mutate { try DomainEngine.setCompletion(of: .task(task.id), complete: task.status != .done, in: &$0) } }
    }

    func toggleMiniTask(_ miniTask: MiniTask) {
        Task { _ = try? await repository.mutate { try DomainEngine.setCompletion(of: .miniTask(miniTask.id), complete: !miniTask.isCompleted, in: &$0) } }
    }

    func updateTask(_ updated: TaskItem) {
        Task {
            _ = try? await repository.mutate { snapshot in
                guard let index = snapshot.tasks.firstIndex(where: { $0.id == updated.id }) else { throw DomainError.taskNotFound }
                let previousStatus = snapshot.tasks[index].status
                var edited = updated
                edited.status = previousStatus
                edited.previousActiveStatus = snapshot.tasks[index].previousActiveStatus
                snapshot.tasks[index] = edited
                if let team = edited.team?.trimmingCharacters(in: .whitespacesAndNewlines), !team.isEmpty,
                   let boardIndex = snapshot.boards.firstIndex(where: { $0.id == edited.boardID }),
                   !snapshot.boards[boardIndex].teams.contains(where: { $0.caseInsensitiveCompare(team) == .orderedSame }) {
                    snapshot.boards[boardIndex].teams.append(team)
                    snapshot.boards[boardIndex].teams.sort()
                }
                snapshot.tasks[index].updatedAt = Date()
                if updated.status != previousStatus {
                    try DomainEngine.move(taskID: updated.id, to: updated.status, in: &snapshot)
                }
            }
        }
    }

    func addMiniTask(to taskID: TaskID) {
        Task {
            _ = try? await repository.mutate { snapshot in
                guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { throw DomainError.taskNotFound }
                let mini = MiniTask(taskID: taskID, title: "New checklist item", order: snapshot.tasks[index].miniTasks.count)
                snapshot.tasks[index].miniTasks.append(mini)
                snapshot.tasks[index].updatedAt = Date()
            }
        }
    }

    func addReference(from source: CompletionTarget, to target: CompletionTarget) {
        Task { _ = try? await repository.mutate { try DomainEngine.addReference(from: source, to: target, in: &$0) } }
    }

    func referenceMembers(for target: CompletionTarget) -> [CompletionTarget] {
        snapshot.referenceGroups.first { $0.members.contains(target) }?.members.sorted { $0.rawID < $1.rawID } ?? []
    }
}
