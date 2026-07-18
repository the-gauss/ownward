import AppKit
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
    var workspaceMode: WorkspaceMode {
        didSet { UserDefaults.standard.set(workspaceMode.rawValue, forKey: "workspaceMode") }
    }
    var selectedTaskID: TaskID?
    var selectedJobRoleID: JobRoleID?
    var viewMode: MainViewMode = .kanban
    var jobSearchScope: JobSearchScope = .all
    var jobSearchSort: JobSearchSort = .nextAction
    var jobTrackFilter: JobTrackFilter = .all
    var searchText = ""
    var jobSearchText = ""
    var projectTaskFilter = TaskFilter()
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
        workspaceMode = UserDefaults.standard.string(forKey: "workspaceMode")
            .flatMap(WorkspaceMode.init(rawValue:)) ?? .projectManagement
        themeChoice = UserDefaults.standard.string(forKey: "appearanceTheme")
            .flatMap(AppThemeChoice.init(rawValue:)) ?? .system
        let savedZoom = UserDefaults.standard.double(forKey: "zoomScale")
        if UserDefaults.standard.integer(forKey: "projectTextScaleVersion") < 2 {
            // The original implementation scaled the entire view hierarchy,
            // including pointer hit regions. Reset that legacy value once as
            // zoom now changes typography and layout naturally.
            zoomScale = 1
            UserDefaults.standard.set(1.0, forKey: "zoomScale")
            UserDefaults.standard.set(2, forKey: "projectTextScaleVersion")
        } else {
            zoomScale = savedZoom == 0 ? 1 : min(ZoomLevel.maximum, max(ZoomLevel.minimum, savedZoom))
        }
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

    var selectedJobRole: JobRole? {
        selectedJobRoleID.flatMap(snapshot.jobSearch.role(id:))
    }

    var visibleJobRoles: [JobRole] {
        JobSearchOrganizer.roles(
            snapshot.jobSearch.roles,
            scope: jobSearchScope,
            track: jobTrackFilter.track,
            search: jobSearchText,
            sort: jobSearchSort
        )
    }

    func jobRoleCount(for scope: JobSearchScope) -> Int {
        JobSearchOrganizer.count(snapshot.jobSearch.roles, scope: scope)
    }

    func activities(for roleID: JobRoleID) -> [JobActivity] {
        snapshot.jobSearch.activities
            .filter { $0.roleID == roleID }
            .sorted { $0.date > $1.date }
    }

    private var scopedTasks: [TaskItem] {
        switch sidebarSelection {
        case .board(let id):
            return snapshot.tasks.filter { $0.boardID == id && TaskStatus.boardColumns.contains($0.status) }
        case .saved(.today):
            let calendar = Calendar.current
            return snapshot.tasks.filter { task in
                guard let date = task.deadlineStart ?? task.deadlineEnd else { return false }
                return calendar.isDateInToday(date) && task.status != .done && task.status != .discarded
            }
        case .saved(.upcoming):
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 14, to: start)!
            return snapshot.tasks.filter { task in
                guard let date = task.deadlineEnd ?? task.deadlineStart else { return false }
                return date >= start && date <= end && task.status != .done && task.status != .discarded
            }
        case .saved(.paused): return snapshot.tasks.filter { $0.status == .paused }
        case .saved(.discarded): return snapshot.tasks.filter { $0.status == .discarded }
        }
    }

    var visibleTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? scopedTasks : scopedTasks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.notesMarkdown.localizedCaseInsensitiveContains(query)
                || ($0.team?.localizedCaseInsensitiveContains(query) == true)
        }
        return TaskOrganizer.filtered(searched, by: projectTaskFilter)
    }

    var availableProjectTeams: [String] {
        Set(scopedTasks.compactMap { task in
            let value = task.team?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var availableProjectStatuses: [TaskStatus] {
        TaskStatus.allCases.filter { status in scopedTasks.contains { $0.status == status } }
    }

    var projectScopeTaskCount: Int { scopedTasks.count }

    var hasUnassignedProjectTasks: Bool {
        scopedTasks.contains { $0.team?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
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
    func setProjectStatusFilter(_ status: TaskStatus?) {
        var filter = projectTaskFilter
        filter.status = status
        projectTaskFilter = filter
    }

    func setProjectTeamFilter(_ team: TaskTeamFilter) {
        var filter = projectTaskFilter
        filter.team = team
        projectTaskFilter = filter
    }

    func setProjectDateFilter(_ date: TaskDateFilter) {
        var filter = projectTaskFilter
        filter.date = date
        projectTaskFilter = filter
    }

    func resetTaskFilters() { projectTaskFilter = TaskFilter() }

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

    func createJobRole(_ role: JobRole) {
        Task {
            do {
                let updated = try await repository.mutate {
                    _ = try JobSearchEngine.upsert(role, in: &$0.jobSearch)
                }
                selectedJobRoleID = updated.jobSearch.roles.first {
                    $0.identity.matches(role.identity)
                }?.id
            } catch {
                apiError = error.localizedDescription
            }
        }
    }

    func updateJobRole(_ role: JobRole) {
        Task {
            do {
                _ = try await repository.mutate {
                    try JobSearchEngine.replace(role, in: &$0.jobSearch)
                }
            } catch {
                apiError = error.localizedDescription
            }
        }
    }

    func setJobStage(_ roleID: JobRoleID, to stage: JobStage) {
        let current = snapshot.jobSearch.role(id: roleID)
        let applicationPatch: JobApplicationPatch?
        if stage.isApplicationStage {
            applicationPatch = JobApplicationPatch(
                applied: true,
                dateApplied: current?.application.dateApplied == nil && stage == .applied ? .value(Date()) : nil
            )
        } else {
            applicationPatch = nil
        }
        mutateJobRole(
            roleID,
            patch: JobRolePatch(application: applicationPatch, stage: stage),
            kind: .stageChanged,
            detail: "Stage changed to \(stage.title)."
        )
    }

    func markJobApplied(_ roleID: JobRoleID) {
        mutateJobRole(
            roleID,
            patch: JobRolePatch(
                application: JobApplicationPatch(applied: true, dateApplied: .value(Date())),
                stage: .applied
            ),
            kind: .applicationUpdated,
            detail: "Marked applied."
        )
    }

    func revealLinkedApplicationTask(for role: JobRole) {
        guard let taskID = role.linkedTaskID, let task = snapshot.task(id: taskID) else {
            apiError = "The linked application task is no longer available."
            return
        }
        switch task.status {
        case .paused:
            sidebarSelection = .saved(.paused)
            viewMode = .table
        case .discarded:
            sidebarSelection = .saved(.discarded)
            viewMode = .table
        case .toDo, .inProgress, .done:
            sidebarSelection = .board(task.boardID)
        }
        selectedTaskID = task.id
        workspaceMode = .projectManagement
    }

    func openPosting(for role: JobRole) {
        openWebURL(role.posting.jobURL, missingMessage: "This opportunity has no direct posting URL.")
    }

    func openCareersPage(for role: JobRole) {
        openWebURL(role.posting.officialCareersURL, missingMessage: "This opportunity has no careers-page URL.")
    }

    func openEvidence(_ evidence: JobEvidence) {
        openWebURL(evidence.url, missingMessage: "This evidence link is not valid.")
    }

    func openContactSource(_ contact: JobContact) {
        openWebURL(contact.sourceURL, missingMessage: "This contact has no public source URL.")
    }

    func openResume(for role: JobRole) {
        guard let sourceURL = JobResumeSourceLocator.resolve(
            recordedPath: role.resume.sourcePath,
            employer: role.employer,
            role: role.role
        ) else {
            apiError = "Ownward could not resolve one unambiguous .tex resume for this role. Update its recorded source path through the weekly job-search workflow."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
    }

    private func mutateJobRole(
        _ roleID: JobRoleID,
        patch: JobRolePatch,
        kind: JobActivityKind,
        detail: String
    ) {
        Task {
            do {
                _ = try await repository.mutate {
                    try JobSearchEngine.update(
                        roleID,
                        patch: patch,
                        activityKind: kind,
                        activityDetail: detail,
                        in: &$0.jobSearch
                    )
                }
            } catch {
                apiError = error.localizedDescription
            }
        }
    }

    private func openWebURL(_ value: String, missingMessage: String) {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            apiError = missingMessage
            return
        }
        NSWorkspace.shared.open(url)
    }

    func referenceMembers(for target: CompletionTarget) -> [CompletionTarget] {
        snapshot.referenceGroups.first { $0.members.contains(target) }?.members.sorted { $0.rawID < $1.rawID } ?? []
    }
}
