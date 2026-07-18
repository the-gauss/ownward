import Foundation
import Testing
@testable import OwnwardCore
@testable import OwnwardServices

@Suite("Automation API")
struct APIRouterTests {
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
