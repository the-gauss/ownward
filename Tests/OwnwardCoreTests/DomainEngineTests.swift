import Foundation
import Testing
@testable import OwnwardCore

@Suite("Completion references")
struct DomainEngineTests {
    @Test("completing a referenced mini-task completes every member")
    func propagatesCompletionAcrossKinds() throws {
        let board = Board(name: "Minkops Kanban")
        var task = TaskItem(boardID: board.id, title: "System Design", status: .inProgress)
        let mini = MiniTask(taskID: task.id, title: "API design")
        task.miniTasks = [mini]
        var source = TaskItem(boardID: board.id, title: "Job Search Ready")
        let sourceMini = MiniTask(taskID: source.id, title: "Finish system design")
        source.miniTasks = [sourceMini]
        var snapshot = OwnwardSnapshot(boards: [board], tasks: [task, source])

        try DomainEngine.addReference(
            from: .miniTask(sourceMini.id),
            to: .miniTask(mini.id),
            in: &snapshot
        )
        try DomainEngine.setCompletion(of: .miniTask(mini.id), complete: true, in: &snapshot)

        #expect(snapshot.miniTask(id: mini.id)?.isCompleted == true)
        #expect(snapshot.miniTask(id: sourceMini.id)?.isCompleted == true)
    }

    @Test("reopening a referenced task restores its previous active column")
    func restoresPreviousStatus() throws {
        let board = Board(name: "Myndral Kanban")
        let first = TaskItem(boardID: board.id, title: "Catalogue", status: .inProgress)
        let second = TaskItem(boardID: board.id, title: "Release", status: .toDo)
        var snapshot = OwnwardSnapshot(boards: [board], tasks: [first, second])
        try DomainEngine.addReference(from: .task(first.id), to: .task(second.id), in: &snapshot)

        try DomainEngine.setCompletion(of: .task(first.id), complete: true, in: &snapshot)
        #expect(snapshot.task(id: first.id)?.status == .done)
        #expect(snapshot.task(id: second.id)?.status == .done)

        try DomainEngine.setCompletion(of: .task(second.id), complete: false, in: &snapshot)
        #expect(snapshot.task(id: first.id)?.status == .inProgress)
        #expect(snapshot.task(id: second.id)?.status == .toDo)
    }

    @Test("reference groups merge without cycles or duplicate members")
    func mergesGroups() throws {
        let board = Board(name: "Minkops Kanban")
        let tasks = ["A", "B", "C"].map { TaskItem(boardID: board.id, title: $0) }
        var snapshot = OwnwardSnapshot(boards: [board], tasks: tasks)

        try DomainEngine.addReference(from: .task(tasks[0].id), to: .task(tasks[1].id), in: &snapshot)
        try DomainEngine.addReference(from: .task(tasks[1].id), to: .task(tasks[2].id), in: &snapshot)
        try DomainEngine.addReference(from: .task(tasks[0].id), to: .task(tasks[2].id), in: &snapshot)

        #expect(snapshot.referenceGroups.count == 1)
        #expect(snapshot.referenceGroups[0].members.count == 3)
    }

    @Test("boards can be created with normalized unique names")
    func createsBoards() throws {
        var snapshot = OwnwardSnapshot.empty

        let board = try DomainEngine.createBoard(named: "  Personal Projects  ", in: &snapshot)

        #expect(board.name == "Personal Projects")
        #expect(snapshot.boards == [board])
        #expect(throws: DomainError.boardAlreadyExists) {
            try DomainEngine.createBoard(named: "personal projects", in: &snapshot)
        }
    }

    @Test("manual reordering persists within a status lane")
    func reordersTasks() throws {
        let board = Board(name: "Minkops Kanban")
        let first = TaskItem(boardID: board.id, title: "First", manualOrder: 0)
        let second = TaskItem(boardID: board.id, title: "Second", manualOrder: 1)
        let third = TaskItem(boardID: board.id, title: "Third", manualOrder: 2)
        var snapshot = OwnwardSnapshot(boards: [board], tasks: [first, second, third])

        try DomainEngine.reorder(taskID: third.id, before: first.id, in: &snapshot)

        #expect(TaskOrganizer.sorted(snapshot.tasks, by: .manual).map(\.title) == ["Third", "First", "Second"])
    }

    @Test("swimlane drops update status and team before manual reordering")
    func relocatesAcrossSwimlanes() throws {
        let board = Board(name: "Minkops Kanban")
        let moving = TaskItem(boardID: board.id, title: "Moving", status: .toDo, team: "A", manualOrder: 0)
        let target = TaskItem(boardID: board.id, title: "Target", status: .inProgress, team: "B", manualOrder: 0)
        var snapshot = OwnwardSnapshot(boards: [board], tasks: [moving, target])

        try DomainEngine.reorder(taskID: moving.id, before: target.id, inTeam: "B", in: &snapshot)

        #expect(snapshot.task(id: moving.id)?.status == .inProgress)
        #expect(snapshot.task(id: moving.id)?.team == "B")
        #expect(TaskOrganizer.sorted(snapshot.tasks.filter { $0.status == .inProgress }, by: .manual).map(\.title) == ["Moving", "Target"])
    }

    @Test("timeline bars shift and resize without producing inverted ranges")
    func editsTimelineDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let board = Board(name: "Minkops Kanban")
        let task = TaskItem(boardID: board.id, title: "System Design", deadlineStart: start, deadlineEnd: end)
        var snapshot = OwnwardSnapshot(boards: [board], tasks: [task])

        try DomainEngine.shiftSchedule(taskID: task.id, byDays: 3, calendar: calendar, in: &snapshot)
        #expect(snapshot.task(id: task.id)?.deadlineStart == calendar.date(byAdding: .day, value: 3, to: start))
        #expect(snapshot.task(id: task.id)?.deadlineEnd == calendar.date(byAdding: .day, value: 3, to: end))

        let laterStart = calendar.date(byAdding: .day, value: 20, to: start)!
        try DomainEngine.resizeSchedule(taskID: task.id, edge: .start, to: laterStart, calendar: calendar, in: &snapshot)
        #expect(snapshot.task(id: task.id)?.deadlineStart == snapshot.task(id: task.id)?.deadlineEnd)

        let earlierEnd = calendar.date(byAdding: .day, value: -20, to: end)!
        try DomainEngine.resizeSchedule(taskID: task.id, edge: .end, to: earlierEnd, calendar: calendar, in: &snapshot)
        #expect(snapshot.task(id: task.id)?.deadlineEnd == snapshot.task(id: task.id)?.deadlineStart)
    }
}
