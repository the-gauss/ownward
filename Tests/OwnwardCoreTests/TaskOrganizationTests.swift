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

    @Test("timeline pointer hit zones distinguish both resize edges from bar movement")
    func timelinePointerHitZones() {
        #expect(TimelineDragMath.operation(at: 4, barWidth: 160, handleWidth: 16) == .resizeStart)
        #expect(TimelineDragMath.operation(at: 80, barWidth: 160, handleWidth: 16) == .move)
        #expect(TimelineDragMath.operation(at: 156, barWidth: 160, handleWidth: 16) == .resizeEnd)
        #expect(TimelineDragMath.operation(at: 8, barWidth: 26, handleWidth: 12) == .resizeStart)
        #expect(TimelineDragMath.operation(at: 9, barWidth: 26, handleWidth: 12) == .move)
        #expect(TimelineDragMath.operation(at: 18, barWidth: 26, handleWidth: 12) == .resizeEnd)
    }

    @Test("timeline drag resolution drives movement and both resize edges")
    func resolvesTimelineDragOperations() {
        let move = TimelineDragMath.resolve(
            startLocation: 64,
            translation: 68,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )
        let resizeStart = TimelineDragMath.resolve(
            startLocation: 6,
            translation: 34,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )
        let resizeEnd = TimelineDragMath.resolve(
            startLocation: 122,
            translation: -34,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )
        let oneDayMove = TimelineDragMath.resolve(
            startLocation: 13,
            translation: 34,
            barWidth: 26,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 1
        )

        #expect(move.operation == .move)
        #expect(move.dayDelta == 2)
        #expect(resizeStart.operation == .resizeStart)
        #expect(resizeStart.dayDelta == 1)
        #expect(resizeEnd.operation == .resizeEnd)
        #expect(resizeEnd.dayDelta == -1)
        #expect(oneDayMove.operation == .move)
        #expect(oneDayMove.dayDelta == 1)
    }

    @Test("timeline drag resolution snaps and clamps resize deltas")
    func snapsAndClampsTimelineDragResolution() {
        let underThreshold = TimelineDragMath.resolve(
            startLocation: 6,
            translation: 16.9,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )
        let halfDay = TimelineDragMath.resolve(
            startLocation: 122,
            translation: -17,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )
        let clampedStart = TimelineDragMath.resolve(
            startLocation: 6,
            translation: 400,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )
        let clampedEnd = TimelineDragMath.resolve(
            startLocation: 122,
            translation: -400,
            barWidth: 128,
            handleWidth: 12,
            dayWidth: 34,
            spanDays: 4
        )

        #expect(underThreshold.dayDelta == 0)
        #expect(halfDay.dayDelta == -1)
        #expect(clampedStart.dayDelta == 3)
        #expect(clampedEnd.dayDelta == -3)
    }

    @Test("project filters combine status, team, and schedule without hiding valid matches")
    func filtersProjectTasks() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 12))!
        let board = Board(name: "Minkops")
        let overdue = TaskItem(
            boardID: board.id,
            title: "Overdue SQL",
            status: .inProgress,
            team: "Interview Prep",
            deadlineEnd: calendar.date(byAdding: .day, value: -1, to: now)
        )
        let today = TaskItem(
            boardID: board.id,
            title: "Today DSA",
            status: .inProgress,
            team: "Interview Prep",
            deadlineEnd: now
        )
        let unscheduled = TaskItem(boardID: board.id, title: "Write docs", status: .toDo, team: nil)
        let doneOverdue = TaskItem(
            boardID: board.id,
            title: "Completed old work",
            status: .done,
            team: "Interview Prep",
            deadlineEnd: calendar.date(byAdding: .day, value: -3, to: now)
        )
        let tasks = [overdue, today, unscheduled, doneOverdue]

        let focused = TaskFilter(
            status: .inProgress,
            team: .named("interview prep"),
            date: .overdue
        )
        #expect(TaskOrganizer.filtered(tasks, by: focused, now: now, calendar: calendar).map(\.title) == ["Overdue SQL"])
        #expect(TaskOrganizer.filtered(tasks, by: TaskFilter(team: .unassigned), now: now, calendar: calendar).map(\.title) == ["Write docs"])
        #expect(TaskOrganizer.filtered(tasks, by: TaskFilter(date: .dueToday), now: now, calendar: calendar).map(\.title) == ["Today DSA"])
        #expect(TaskOrganizer.filtered(tasks, by: TaskFilter(date: .overdue), now: now, calendar: calendar).map(\.title) == ["Overdue SQL"])
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

    @Test("checklist children follow the parent subtree and retain nesting")
    func addsChecklistSubtaskAfterExistingDescendants() throws {
        let board = Board(name: "Minkops")
        var task = TaskItem(boardID: board.id, title: "Plan")
        let parent = ChecklistEditor.addItem(to: &task, title: "Parent")
        let existingChild = try ChecklistEditor.addSubtask(to: parent.id, in: &task, title: "Existing child")
        _ = try ChecklistEditor.addSubtask(to: existingChild.id, in: &task, title: "Grandchild")

        let newChild = try ChecklistEditor.addSubtask(to: parent.id, in: &task, title: "New child")

        #expect(task.miniTasks.map(\.title) == ["Parent", "Existing child", "Grandchild", "New child"])
        #expect(task.miniTasks.map(\.depth) == [0, 1, 2, 1])
        #expect(task.miniTasks.map(\.order) == [0, 1, 2, 3])
        #expect(newChild.taskID == task.id)
    }

    @Test("deleting a checklist item removes its descendants and normalizes order")
    func deletesChecklistSubtree() throws {
        let board = Board(name: "Minkops")
        var task = TaskItem(boardID: board.id, title: "Plan")
        let parent = ChecklistEditor.addItem(to: &task, title: "Parent")
        let child = try ChecklistEditor.addSubtask(to: parent.id, in: &task, title: "Child")
        _ = try ChecklistEditor.addSubtask(to: child.id, in: &task, title: "Grandchild")
        let sibling = ChecklistEditor.addItem(to: &task, title: "Sibling")

        let removed = try ChecklistEditor.removeItem(parent.id, from: &task)

        #expect(removed.count == 3)
        #expect(task.miniTasks.map(\.id) == [sibling.id])
        #expect(task.miniTasks.map(\.order) == [0])
        #expect(task.miniTasks.map(\.depth) == [0])
    }

    @Test("deleting a checklist subtree removes stale completion references")
    func removesDeletedChecklistReferences() throws {
        let board = Board(name: "Minkops")
        var task = TaskItem(boardID: board.id, title: "Plan")
        let parent = ChecklistEditor.addItem(to: &task, title: "Parent")
        let child = try ChecklistEditor.addSubtask(to: parent.id, in: &task, title: "Child")
        var otherTask = TaskItem(boardID: board.id, title: "Review")
        let otherMiniTask = ChecklistEditor.addItem(to: &otherTask, title: "Review plan")
        var snapshot = OwnwardSnapshot(boards: [board], tasks: [task, otherTask])
        try DomainEngine.addReference(
            from: .miniTask(child.id),
            to: .miniTask(otherMiniTask.id),
            in: &snapshot
        )

        let removed = try ChecklistEditor.removeItem(parent.id, from: &snapshot.tasks[0])
        ChecklistEditor.removeReferences(to: Set(removed), from: &snapshot)

        #expect(snapshot.referenceGroups.isEmpty)
        #expect(snapshot.miniTask(id: otherMiniTask.id)?.isCompleted == false)
    }
}
