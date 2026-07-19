import Foundation
import Testing
@testable import OwnwardCore
@testable import OwnwardServices

@Suite("Automation API")
struct APIRouterTests {
    actor RecordingScheduledLogNotifier: ScheduledLogNotifier {
        private(set) var entries: [ScheduledLogEntry] = []

        func notify(of entry: ScheduledLogEntry) async {
            entries.append(entry)
        }
    }

    @Test("scheduled logs persist Markdown and enforce daily retention")
    func writesScheduledLogs() async throws {
        let repository = try WorkspaceRepository(inMemory: .empty)
        let notifier = RecordingScheduledLogNotifier()
        let router = APIRouter(repository: repository, token: "secret", scheduledLogNotifier: notifier)
        let headers = ["authorization": "Bearer secret"]

        for index in 1...5 {
            let response = await router.handle(APIRequest(
                method: "POST",
                path: "/v1/scheduled-logs",
                headers: headers,
                body: try JSONEncoder.api.encode(CreateScheduledLogRequest(
                    kind: .dailyDayStarter,
                    markdown: "# Daily \(index)"
                ))
            ))
            #expect(response.status == 201)
        }

        let logs = await repository.snapshot().scheduledLogs
        #expect(logs.count == 4)
        #expect(logs.allSatisfy { $0.kind == .dailyDayStarter })
        #expect((await notifier.entries).count == 5)
    }

    @Test("job-search context is a complete durable replacement for tracker memory")
    func jobSearchContext() async throws {
        let role = JobRole(
            track: .backup,
            priority: 1,
            employer: "Wesway",
            role: "Data Specialist",
            posting: JobPosting(jobURL: "https://example.ca/jobs/1"),
            application: JobApplication(applied: true, notes: "Preserve this")
        )
        let activity = JobActivity(roleID: role.id, kind: .created, detail: "Migrated")
        let repository = try WorkspaceRepository(inMemory: OwnwardSnapshot(
            jobSearch: JobSearchWorkspace(roles: [role], activities: [activity])
        ))
        let router = APIRouter(repository: repository, token: "secret")

        let response = await router.handle(APIRequest(
            method: "GET",
            path: "/v1/job-search/context",
            headers: ["authorization": "Bearer secret"]
        ))

        let context = try JSONDecoder.api.decode(JobSearchContext.self, from: response.body)
        #expect(response.status == 200)
        #expect(context.roles.map(\.id) == [role.id])
        #expect(context.roles.first?.application.notes == "Preserve this")
        #expect(context.activities.map(\.id) == [activity.id])
        #expect(context.activities.first?.detail == "Migrated")
    }

    @Test("job-role list supports track, stage, scope, and human search filters")
    func listsFilteredJobRoles() async throws {
        var ready = JobRole(
            track: .backup,
            employer: "Example County",
            role: "Data Analyst",
            location: JobLocation(city: "Thunder Bay", province: "ON"),
            posting: JobPosting(jobURL: "https://example.ca/a"),
            stage: .readyToApply
        )
        ready.application.notes = "municipal referral"
        let closed = JobRole(
            track: .canon,
            employer: "Other Co",
            role: "Engineer",
            posting: JobPosting(jobURL: "https://example.ca/b"),
            stage: .closed
        )
        let repository = try WorkspaceRepository(inMemory: OwnwardSnapshot(
            jobSearch: JobSearchWorkspace(roles: [closed, ready])
        ))
        let router = APIRouter(repository: repository, token: "secret")

        let response = await router.handle(APIRequest(
            method: "GET",
            path: "/v1/job-search/roles",
            query: ["track": "backup", "scope": "needsAction", "search": "municipal"],
            headers: ["authorization": "Bearer secret"]
        ))
        let roles = try JSONDecoder.api.decode([JobRole].self, from: response.body)

        #expect(roles.map(\.employer) == ["Example County"])
    }

    @Test("job-role upsert and patch preserve application history and support explicit nulls")
    func writesJobRolesSafely() async throws {
        let repository = try WorkspaceRepository(inMemory: .empty)
        let router = APIRouter(repository: repository, token: "secret")
        let headers = ["authorization": "Bearer secret"]
        var request = UpsertJobRoleRequest(
            track: .backup,
            priority: 1,
            employer: "Wesway",
            role: "Data Specialist",
            location: JobLocation(city: "Thunder Bay", province: "ON"),
            posting: JobPosting(status: "Open", jobURL: "https://example.ca/job"),
            stage: .readyToApply
        )

        let createdResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/job-search/roles/upsert",
            headers: headers,
            body: try JSONEncoder.api.encode(request)
        ))
        let created = try JSONDecoder.api.decode(JobRole.self, from: createdResponse.body)
        let appliedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let patchResponse = await router.handle(APIRequest(
            method: "PATCH",
            path: "/v1/job-search/roles/\(created.id)",
            headers: headers,
            body: try JSONEncoder.api.encode(UpdateJobRoleRequest(
                patch: JobRolePatch(
                    application: JobApplicationPatch(
                        applied: true,
                        dateApplied: .value(appliedAt),
                        followUpDate: .value(appliedAt.addingTimeInterval(86_400)),
                        notes: "Submitted by me"
                    ),
                    stage: .applied
                ),
                activityKind: .applicationUpdated,
                activityDetail: "Marked applied"
            ))
        ))
        #expect(patchResponse.status == 200)

        request.posting.status = "Open — reverified"
        let refreshedResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/job-search/roles/upsert",
            headers: headers,
            body: try JSONEncoder.api.encode(request)
        ))
        let refreshed = try JSONDecoder.api.decode(JobRole.self, from: refreshedResponse.body)
        #expect(refreshed.id == created.id)
        #expect(refreshed.application.notes == "Submitted by me")
        #expect(refreshed.stage == .applied)

        let clearedResponse = await router.handle(APIRequest(
            method: "PATCH",
            path: "/v1/job-search/roles/\(created.id)",
            headers: headers,
            body: try JSONEncoder.api.encode(UpdateJobRoleRequest(
                patch: JobRolePatch(application: JobApplicationPatch(followUpDate: .null))
            ))
        ))
        let cleared = try JSONDecoder.api.decode(JobRole.self, from: clearedResponse.body)
        #expect(cleared.application.followUpDate == nil)
        #expect(cleared.application.dateApplied == appliedAt)
    }

    @Test("day starter context includes active tasks and structured mini-tasks")
    func dayStarterContext() async throws {
        let board = Board(name: "Minkops Kanban")
        var active = TaskItem(boardID: board.id, title: "Leetcode SQL", status: .inProgress)
        active.miniTasks = [MiniTask(taskID: active.id, title: "Solve seven problems")]
        let done = TaskItem(boardID: board.id, title: "Old task", status: .done)
        let repository = try WorkspaceRepository(inMemory: OwnwardSnapshot(boards: [board], tasks: [active, done]))
        let router = APIRouter(repository: repository, token: "secret")

        let response = await router.handle(APIRequest(method: "GET", path: "/v1/day-starter/context", headers: ["authorization": "Bearer secret"]))

        #expect(response.status == 200)
        let context = try JSONDecoder.api.decode(DayStarterContext.self, from: response.body)
        #expect(context.tasks.map(\.title) == ["Leetcode SQL"])
        #expect(context.tasks[0].miniTasks.count == 1)
        #expect(context.referenceGroups.isEmpty)
    }

    @Test("write routes reject missing bearer token")
    func requiresAuthentication() async throws {
        let repository = try WorkspaceRepository(inMemory: .empty)
        let router = APIRouter(repository: repository, token: "secret")
        let response = await router.handle(APIRequest(method: "POST", path: "/v1/tasks", body: Data("{}".utf8)))
        #expect(response.status == 401)
    }

    @Test("public JSON uses string identifiers and ISO dates")
    func publicJSONShape() throws {
        let board = Board(name: "Minkops Kanban")
        let task = TaskItem(boardID: board.id, title: "System Design", team: "Interview Prep", deadlineStart: Date(timeIntervalSince1970: 1_700_000_000))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder.api.encode(task)) as? [String: Any])
        #expect(object["id"] is String)
        #expect(object["boardID"] is String)
        #expect(object.keys.contains("team"))
        #expect(!object.keys.contains("workstream"))
        #expect((object["deadlineStart"] as? String)?.contains("T") == true)
    }

    @Test("boards and categorized mini-tasks can be created through the API")
    func createsBoardAndCategorizedMiniTask() async throws {
        let repository = try WorkspaceRepository(inMemory: .empty)
        let router = APIRouter(repository: repository, token: "secret")
        let headers = ["authorization": "Bearer secret"]

        let boardResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/boards",
            headers: headers,
            body: try JSONEncoder.api.encode(CreateBoardRequest(name: "Personal"))
        ))
        let board = try JSONDecoder.api.decode(Board.self, from: boardResponse.body)
        let taskResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/tasks",
            headers: headers,
            body: try JSONEncoder.api.encode(CreateTaskRequest(boardID: board.id, title: "Algorithms", team: "Study"))
        ))
        let task = try JSONDecoder.api.decode(TaskItem.self, from: taskResponse.body)
        let miniResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/tasks/\(task.id)/mini-tasks",
            headers: headers,
            body: try JSONEncoder.api.encode(CreateMiniTaskRequest(title: "Two Sum", category: "Arrays"))
        ))
        let mini = try JSONDecoder.api.decode(MiniTask.self, from: miniResponse.body)

        #expect(boardResponse.status == 201)
        #expect(task.team == "Study")
        #expect(mini.category == "Arrays")
    }

    @Test("swimlane moves update status, team, and manual order atomically")
    func atomicSwimlaneMove() async throws {
        let board = Board(name: "Minkops Kanban")
        let moving = TaskItem(boardID: board.id, title: "Moving", status: .toDo, team: "Interview Prep", manualOrder: 0)
        let target = TaskItem(boardID: board.id, title: "Target", status: .inProgress, team: "Tutorials", manualOrder: 0)
        let repository = try WorkspaceRepository(inMemory: OwnwardSnapshot(boards: [board], tasks: [moving, target]))
        let router = APIRouter(repository: repository, token: "secret")

        let response = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/tasks/\(moving.id)/move",
            headers: ["authorization": "Bearer secret"],
            body: try JSONEncoder.api.encode(MoveTaskRequest(
                status: .inProgress,
                team: "Tutorials",
                beforeTaskID: target.id
            ))
        ))

        let updated = try JSONDecoder.api.decode(TaskItem.self, from: response.body)
        let snapshot = await repository.snapshot()
        #expect(response.status == 200)
        #expect(updated.status == .inProgress)
        #expect(updated.team == "Tutorials")
        #expect(snapshot.task(id: moving.id)?.manualOrder == 0)
        #expect(snapshot.task(id: target.id)?.manualOrder == 1)
    }

    @Test("timeline schedule routes shift and clamp resized edges")
    func timelineScheduleRoutes() async throws {
        let board = Board(name: "Minkops Kanban")
        let calendar = Calendar(identifier: .gregorian)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 10)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12)))
        let task = TaskItem(boardID: board.id, title: "Timeline", deadlineStart: start, deadlineEnd: end)
        let repository = try WorkspaceRepository(inMemory: OwnwardSnapshot(boards: [board], tasks: [task]))
        let router = APIRouter(repository: repository, token: "secret")
        let headers = ["authorization": "Bearer secret"]

        let shiftedResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/tasks/\(task.id)/schedule/shift",
            headers: headers,
            body: try JSONEncoder.api.encode(ShiftTaskScheduleRequest(days: 3))
        ))
        let shifted = try JSONDecoder.api.decode(TaskItem.self, from: shiftedResponse.body)
        #expect(calendar.dateComponents([.day], from: start, to: shifted.deadlineStart!).day == 3)
        #expect(calendar.dateComponents([.day], from: end, to: shifted.deadlineEnd!).day == 3)

        let afterEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 30)))
        let resizedResponse = await router.handle(APIRequest(
            method: "POST",
            path: "/v1/tasks/\(task.id)/schedule/resize",
            headers: headers,
            body: try JSONEncoder.api.encode(ResizeTaskScheduleRequest(edge: .start, date: afterEnd))
        ))
        let resized = try JSONDecoder.api.decode(TaskItem.self, from: resizedResponse.body)
        #expect(resized.deadlineStart == resized.deadlineEnd)
    }
}
