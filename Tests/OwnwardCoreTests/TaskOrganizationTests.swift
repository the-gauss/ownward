import Foundation
import Testing
@testable import OwnwardCore

@Suite("Task organization")
struct TaskOrganizationTests {
    @Test("deadline and progress sorting are deterministic")
    func sortsTasks() {
        let board = Board(name: "Minkops")
        let later = TaskItem(boardID: board.id, title: "Later", deadlineStart: Date(timeIntervalSince1970: 300), miniTasks: [
            MiniTask(taskID: TaskID(), title: "A", isCompleted: true)
        ])
        let sooner = TaskItem(boardID: board.id, title: "Sooner", deadlineStart: Date(timeIntervalSince1970: 100), miniTasks: [
            MiniTask(taskID: TaskID(), title: "A"), MiniTask(taskID: TaskID(), title: "B")
        ])

        #expect(TaskOrganizer.sorted([later, sooner], by: .deadline).map(\.title) == ["Sooner", "Later"])
        #expect(TaskOrganizer.sorted([later, sooner], by: .checklistProgress).map(\.title) == ["Sooner", "Later"])
    }

    @Test("tasks group by status or team")
    func groupsTasks() {
        let board = Board(name: "Minkops")
        let design = TaskItem(boardID: board.id, title: "Design", status: .inProgress, team: "Interview Prep")
        let api = TaskItem(boardID: board.id, title: "API", status: .toDo, team: "Engineering")

        #expect(TaskOrganizer.grouped([design, api], by: .status).map(\.title) == ["To Do", "In Progress"])
        #expect(TaskOrganizer.grouped([design, api], by: .team).map(\.title) == ["Engineering", "Interview Prep"])
    }

    @Test("team swimlanes align every status at one shared level")
    func alignsTeamSwimlanes() {
        let board = Board(name: "Minkops")
        let tasks = [
            TaskItem(boardID: board.id, title: "Plan", status: .toDo, team: "Platform", manualOrder: 1),
            TaskItem(boardID: board.id, title: "Build", status: .inProgress, team: "Platform", manualOrder: 0),
            TaskItem(boardID: board.id, title: "Ship", status: .done, team: "Platform", manualOrder: 2),
            TaskItem(boardID: board.id, title: "Apply", status: .toDo, team: "Job Search", manualOrder: 0)
        ]

        let lanes = TaskOrganizer.teamSwimlanes(tasks, sort: .manual)

        #expect(lanes.map(\.team) == ["Job Search", "Platform"])
        #expect(lanes[1].tasks(in: .toDo).map(\.title) == ["Plan"])
        #expect(lanes[1].tasks(in: .inProgress).map(\.title) == ["Build"])
        #expect(lanes[1].tasks(in: .done).map(\.title) == ["Ship"])
    }

    @Test("default order is available as the reset sort")
    func exposesDefaultSort() {
        #expect(TaskSort.manual.title == "Default Order")
    }

    @Test("timeline spans use inclusive calendar-day geometry")
    func timelineGeometry() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let scale = TimelineScale(start: start, end: end, calendar: calendar)

        #expect(scale.dayOffset(for: start) == 0)
        #expect(scale.spanDays(from: start, through: end) == 4)
        #expect(scale.totalDays == 4)
    }

    @Test("timeline drag snapping preserves at least one day while resizing")
    func timelineDragSnapping() {
        #expect(TimelineDragMath.dayDelta(translation: 33, dayWidth: 34, operation: .move, spanDays: 4) == 1)
        #expect(TimelineDragMath.dayDelta(translation: 400, dayWidth: 34, operation: .resizeStart, spanDays: 4) == 3)
        #expect(TimelineDragMath.dayDelta(translation: -400, dayWidth: 34, operation: .resizeEnd, spanDays: 4) == -3)
    }

    @Test("uncategorized first checklist items form a safe initial group")
    func groupsUncategorizedChecklistItems() {
        let taskID = TaskID()
        let items = [
            MiniTask(taskID: taskID, title: "First", order: 0),
            MiniTask(taskID: taskID, title: "Second", order: 1),
            MiniTask(taskID: taskID, title: "Third", order: 2, category: "Math"),
        ]

        let groups = ChecklistOrganizer.grouped(items)

        #expect(groups.count == 2)
        #expect(groups[0].category == nil)
        #expect(groups[0].items.map(\.title) == ["First", "Second"])
        #expect(groups[1].category == "Math")
    }
}
