import Foundation
import OwnwardCore

public struct APIRouter: Sendable {
    private let repository: WorkspaceRepository
    private let token: String
    private let scheduledLogNotifier: any ScheduledLogNotifier

    public init(
        repository: WorkspaceRepository,
        token: String,
        scheduledLogNotifier: any ScheduledLogNotifier = NoopScheduledLogNotifier()
    ) {
        self.repository = repository
        self.token = token
        self.scheduledLogNotifier = scheduledLogNotifier
    }

    public func handle(_ request: APIRequest) async -> APIResponse {
        if request.path == "/v1/health" { return .json(HealthResponse()) }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return .error(status: 401, message: "A valid local API token is required.")
        }

        do {
            switch (request.method, request.path) {
            case ("GET", "/v1/boards"):
                return .json(await repository.snapshot().boards)
            case ("GET", "/v1/tasks"):
                return .json(filterTasks(in: await repository.snapshot(), query: request.query))
            case ("GET", "/v1/references"):
                return .json(await repository.snapshot().referenceGroups)
            case ("POST", "/v1/tasks"):
                return try await createTask(from: request.body)
            case ("POST", "/v1/scheduled-logs"):
                return try await createScheduledLog(from: request.body)
            case ("POST", "/v1/boards"):
                return try await createBoard(from: request.body)
            case ("GET", "/v1/day-starter/context"):
                let snapshot = await repository.snapshot()
                let tasks = snapshot.tasks
                    .filter { $0.status == .toDo || $0.status == .inProgress }
                    .sorted(by: taskPriority)
                return .json(DayStarterContext(boards: snapshot.boards, tasks: tasks, referenceGroups: snapshot.referenceGroups))
            case ("GET", "/v1/job-search/context"):
                let workspace = await repository.snapshot().jobSearch
                return .json(JobSearchContext(
                    roles: workspace.roles,
                    activities: workspace.activities,
                    contacts: workspace.contacts
                ))
            case ("GET", "/v1/job-search/roles"):
                return .json(filterJobRoles(in: await repository.snapshot(), query: request.query))
            case ("GET", "/v1/job-search/contacts"):
                return .json(filterJobSearchContacts(in: await repository.snapshot(), query: request.query))
            case ("POST", "/v1/job-search/roles/upsert"):
                return try await upsertJobRole(from: request.body)
            case ("POST", "/v1/references"):
                return try await createReference(from: request.body)
            case ("POST", "/v1/completion"):
                return try await setCompletion(from: request.body)
            default:
                return try await handleParameterizedRoute(request)
            }
        } catch let error as DecodingError {
            return .error(status: 400, message: "Invalid JSON: \(error.localizedDescription)")
        } catch let error as DomainError {
            let status = error == .invalidBoardName || error == .boardAlreadyExists
                || error == .invalidJobRole || error == .invalidJobContact ? 400 : 404
            return .error(status: status, message: error.localizedDescription)
        } catch {
            return .error(status: 500, message: error.localizedDescription)
        }
    }

    private func handleParameterizedRoute(_ request: APIRequest) async throws -> APIResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        if parts.count == 4, parts[0] == "v1", parts[1] == "job-search", parts[2] == "roles" {
            guard let uuid = UUID(uuidString: parts[3]) else { throw DomainError.jobRoleNotFound }
            let id = JobRoleID(rawValue: uuid)
            if request.method == "GET" {
                guard let role = await repository.snapshot().jobSearch.role(id: id) else {
                    throw DomainError.jobRoleNotFound
                }
                return .json(role)
            }
            if request.method == "PATCH" {
                return try await updateJobRole(id: id, body: request.body)
            }
        }
        if parts.count == 3, parts[0] == "v1", parts[1] == "tasks", request.method == "GET" {
            guard let id = taskID(parts[2]), let task = await repository.snapshot().task(id: id) else {
                throw DomainError.taskNotFound
            }
            return .json(task)
        }
        if parts.count == 3, parts[0] == "v1", parts[1] == "tasks", request.method == "PATCH" {
            guard let id = taskID(parts[2]) else { throw DomainError.taskNotFound }
            return try await updateTask(id: id, body: request.body)
        }
        if parts.count == 4, parts[0] == "v1", parts[1] == "tasks", parts[3] == "move", request.method == "POST" {
            guard let id = taskID(parts[2]) else { throw DomainError.taskNotFound }
            let payload = try JSONDecoder.ownward.decode(MoveTaskRequest.self, from: request.body)
            let current = await repository.snapshot()
            guard let moving = current.task(id: id) else { throw DomainError.taskNotFound }
            let destinationTeam = payload.team ?? moving.team
            if let beforeTaskID = payload.beforeTaskID {
                guard let target = current.task(id: beforeTaskID) else { throw DomainError.taskNotFound }
                guard target.status == payload.status else {
                    return .error(status: 400, message: "The manual-order target must be in the requested status.")
                }
            }
            let snapshot = try await repository.mutate { snapshot in
                if let beforeTaskID = payload.beforeTaskID {
                    try DomainEngine.reorder(taskID: id, before: beforeTaskID, inTeam: destinationTeam, in: &snapshot)
                } else if payload.team != nil {
                    try DomainEngine.move(taskID: id, to: payload.status, team: destinationTeam, in: &snapshot)
                } else {
                    try DomainEngine.move(taskID: id, to: payload.status, in: &snapshot)
                }
            }
            return .json(snapshot.task(id: id)!)
        }
        if parts.count == 5, parts[0] == "v1", parts[1] == "tasks", parts[3] == "schedule", parts[4] == "shift", request.method == "POST" {
            guard let id = taskID(parts[2]) else { throw DomainError.taskNotFound }
            let payload = try JSONDecoder.api.decode(ShiftTaskScheduleRequest.self, from: request.body)
            let snapshot = try await repository.mutate {
                try DomainEngine.shiftSchedule(taskID: id, byDays: payload.days, calendar: Self.apiCalendar, in: &$0)
            }
            return .json(snapshot.task(id: id)!)
        }
        if parts.count == 5, parts[0] == "v1", parts[1] == "tasks", parts[3] == "schedule", parts[4] == "resize", request.method == "POST" {
            guard let id = taskID(parts[2]) else { throw DomainError.taskNotFound }
            let payload = try JSONDecoder.api.decode(ResizeTaskScheduleRequest.self, from: request.body)
            let snapshot = try await repository.mutate {
                try DomainEngine.resizeSchedule(taskID: id, edge: payload.edge, to: payload.date, calendar: Self.apiCalendar, in: &$0)
            }
            return .json(snapshot.task(id: id)!)
        }
        if parts.count == 4, parts[0] == "v1", parts[1] == "tasks", parts[3] == "mini-tasks", request.method == "POST" {
            guard let id = taskID(parts[2]) else { throw DomainError.taskNotFound }
            return try await createMiniTask(taskID: id, body: request.body)
        }
        if parts.count == 3, parts[0] == "v1", parts[1] == "mini-tasks", request.method == "PATCH" {
            guard let uuid = UUID(uuidString: parts[2]) else { throw DomainError.miniTaskNotFound }
            return try await updateMiniTask(id: MiniTaskID(rawValue: uuid), body: request.body)
        }
        return .error(status: 404, message: "Route not found.")
    }

    private func createTask(from body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(CreateTaskRequest.self, from: body)
        let existing = await repository.snapshot()
        guard existing.boards.contains(where: { $0.id == request.boardID }) else { throw DomainError.boardNotFound }
        let taskID = TaskID()
        let parsed = MarkdownChecklistParser.parse(request.notesMarkdown ?? "", taskID: taskID)
        var task = TaskItem(
            id: taskID,
            boardID: request.boardID,
            title: request.title,
            status: request.status ?? .toDo,
            team: request.team ?? request.workstream,
            deadlineStart: request.deadlineStart,
            deadlineEnd: request.deadlineEnd,
            notesMarkdown: parsed.notesMarkdown,
            links: parsed.links
        )
        task.miniTasks = parsed.miniTasks
        let createdTask = task
        _ = try await repository.mutate { $0.tasks.append(createdTask) }
        return .json(createdTask, status: 201)
    }

    private func createScheduledLog(from body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(CreateScheduledLogRequest.self, from: body)
        guard !request.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error(status: 400, message: "A scheduled log requires Markdown content.")
        }
        let entry = ScheduledLogEntry(kind: request.kind, markdown: request.markdown)
        _ = try await repository.mutate { snapshot in
            snapshot.scheduledLogs = ScheduledLogRetention.adding(entry, to: snapshot.scheduledLogs)
        }
        await scheduledLogNotifier.notify(of: entry)
        return .json(entry, status: 201)
    }

    private func upsertJobRole(from body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(UpsertJobRoleRequest.self, from: body)
        let incoming = request.roleValue()
        let existed = await repository.snapshot().jobSearch.roles.contains {
            $0.identity.matches(incoming.identity)
        }
        let snapshot = try await repository.mutate {
            _ = try JobSearchEngine.upsert(incoming, in: &$0.jobSearch)
        }
        guard let role = snapshot.jobSearch.roles.first(where: { $0.identity.matches(incoming.identity) }) else {
            throw DomainError.jobRoleNotFound
        }
        return .json(role, status: existed ? 200 : 201)
    }

    private func updateJobRole(id: JobRoleID, body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(UpdateJobRoleRequest.self, from: body)
        let snapshot = try await repository.mutate {
            try JobSearchEngine.update(
                id,
                patch: request.patch,
                activityKind: request.activityKind,
                activityDetail: request.activityDetail,
                in: &$0.jobSearch
            )
        }
        guard let role = snapshot.jobSearch.role(id: id) else { throw DomainError.jobRoleNotFound }
        return .json(role)
    }

    private func updateTask(id: TaskID, body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(UpdateTaskRequest.self, from: body)
        let snapshot = try await repository.mutate { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else { throw DomainError.taskNotFound }
            if let title = request.title { snapshot.tasks[index].title = title }
            if let team = request.team ?? request.workstream { snapshot.tasks[index].team = team }
            if let deadlineStart = request.deadlineStart { snapshot.tasks[index].deadlineStart = deadlineStart }
            if let deadlineEnd = request.deadlineEnd { snapshot.tasks[index].deadlineEnd = deadlineEnd }
            if let notes = request.notesMarkdown { snapshot.tasks[index].notesMarkdown = notes }
            if let links = request.links { snapshot.tasks[index].links = links }
            snapshot.tasks[index].updatedAt = Date()
            if let status = request.status { try DomainEngine.move(taskID: id, to: status, in: &snapshot) }
        }
        return .json(snapshot.task(id: id)!)
    }

    private func createMiniTask(taskID: TaskID, body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(CreateMiniTaskRequest.self, from: body)
        let current = await repository.snapshot()
        guard let task = current.task(id: taskID) else { throw DomainError.taskNotFound }
        let created = MiniTask(taskID: taskID, title: request.title, isCompleted: request.isCompleted ?? false, depth: request.depth ?? 0, order: task.miniTasks.count, category: request.category)
        _ = try await repository.mutate { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { throw DomainError.taskNotFound }
            snapshot.tasks[index].miniTasks.append(created)
            snapshot.tasks[index].updatedAt = Date()
        }
        return .json(created, status: 201)
    }

    private func updateMiniTask(id: MiniTaskID, body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(UpdateMiniTaskRequest.self, from: body)
        let snapshot = try await repository.mutate { snapshot in
            guard let taskIndex = snapshot.tasks.firstIndex(where: { task in task.miniTasks.contains(where: { $0.id == id }) }),
                  let miniIndex = snapshot.tasks[taskIndex].miniTasks.firstIndex(where: { $0.id == id }) else {
                throw DomainError.miniTaskNotFound
            }
            if let title = request.title { snapshot.tasks[taskIndex].miniTasks[miniIndex].title = title }
            if let depth = request.depth { snapshot.tasks[taskIndex].miniTasks[miniIndex].depth = max(0, depth) }
            if let category = request.category { snapshot.tasks[taskIndex].miniTasks[miniIndex].category = category.isEmpty ? nil : category }
            if let completed = request.isCompleted {
                try DomainEngine.setCompletion(of: .miniTask(id), complete: completed, in: &snapshot)
            }
        }
        guard let updated = snapshot.miniTask(id: id) else { throw DomainError.miniTaskNotFound }
        return .json(updated)
    }

    private func createReference(from body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(CreateReferenceRequest.self, from: body)
        let source = try request.source.completionTarget()
        let target = try request.target.completionTarget()
        let snapshot = try await repository.mutate { try DomainEngine.addReference(from: source, to: target, in: &$0) }
        return .json(ReferenceResponse(groups: snapshot.referenceGroups), status: 201)
    }

    private func createBoard(from body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(CreateBoardRequest.self, from: body)
        let snapshot = try await repository.mutate { _ = try DomainEngine.createBoard(named: request.name, in: &$0) }
        guard let board = snapshot.boards.last else { throw DomainError.boardNotFound }
        return .json(board, status: 201)
    }

    private func setCompletion(from body: Data) async throws -> APIResponse {
        let request = try JSONDecoder.api.decode(SetCompletionRequest.self, from: body)
        let target = try request.target.completionTarget()
        let snapshot = try await repository.mutate { try DomainEngine.setCompletion(of: target, complete: request.complete, in: &$0) }
        switch target {
        case .task(let id): return .json(snapshot.task(id: id)!)
        case .miniTask(let id): return .json(snapshot.miniTask(id: id)!)
        }
    }

    private func filterTasks(in snapshot: OwnwardSnapshot, query: [String: String]) -> [TaskItem] {
        snapshot.tasks.filter { task in
            let boardMatches = query["board_id"].flatMap(UUID.init(uuidString:)).map { task.boardID.rawValue == $0 } ?? true
            let statusMatches = query["status"].flatMap(TaskStatus.init(rawValue:)).map { task.status == $0 } ?? true
            let searchMatches = query["search"].map { task.title.localizedCaseInsensitiveContains($0) || task.notesMarkdown.localizedCaseInsensitiveContains($0) } ?? true
            let teamMatches = query["team"].map { task.team?.localizedCaseInsensitiveCompare($0) == .orderedSame } ?? true
            return boardMatches && statusMatches && searchMatches && teamMatches
        }.sorted(by: taskPriority)
    }

    private func filterJobRoles(in snapshot: OwnwardSnapshot, query: [String: String]) -> [JobRole] {
        let scope = query["scope"].flatMap(JobSearchScope.init(rawValue:)) ?? .all
        let track = query["track"].flatMap(JobSearchTrack.init(rawValue:))
        let sort = query["sort"].flatMap(JobSearchSort.init(rawValue:)) ?? .nextAction
        let organized = JobSearchOrganizer.roles(
            snapshot.jobSearch.roles,
            scope: scope,
            track: track,
            search: query["search"] ?? "",
            sort: sort
        )
        guard let stage = query["stage"].flatMap(JobStage.init(rawValue:)) else { return organized }
        return organized.filter { $0.stage == stage }
    }

    private func filterJobSearchContacts(in snapshot: OwnwardSnapshot, query: [String: String]) -> [JobSearchContact] {
        let filter = JobSearchContactFilter(
            usefulness: query["usefulness"].flatMap(JobContactUsefulness.init(rawValue:)),
            responseStatus: query["response_status"].flatMap(JobContactResponseStatus.init(rawValue:)),
            relationshipLevel: query["relationship_level"].flatMap(Int.init),
            followUp: query["follow_up"].flatMap(JobSearchContactFollowUpFilter.init(rawValue:)) ?? .all,
            scope: query["scope"].flatMap(JobSearchContactScope.init(rawValue:)) ?? .active
        )
        let sort = query["sort"].flatMap(JobSearchContactSort.init(rawValue:)) ?? .relationshipLevel
        return JobSearchContactOrganizer.contacts(
            snapshot.jobSearch.contacts,
            filter: filter,
            search: query["search"] ?? "",
            sort: sort
        )
    }

    private func taskPriority(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.deadlineEnd ?? lhs.deadlineStart, rhs.deadlineEnd ?? rhs.deadlineStart) {
        case (let left?, let right?): left < right
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.updatedAt > rhs.updatedAt
        }
    }

    private func taskID(_ value: String) -> TaskID? {
        UUID(uuidString: value).map(TaskID.init(rawValue:))
    }

    private static var apiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
