import Foundation
import Testing
@testable import OwnwardApp
@testable import OwnwardCore
@testable import OwnwardServices

@Suite("Job Search presentation policy")
struct JobSearchPresentationTests {
    @Test("project task commands are unavailable in Job Search mode")
    func workspaceCommandScope() {
        #expect(WorkspaceMode.projectManagement.supportsProjectControls)
        #expect(!WorkspaceMode.jobSearch.supportsProjectControls)
    }

    @Test("a linked application task opens in its Project Management destination")
    @MainActor
    func linkedApplicationTaskNavigation() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: "workspaceMode")
        defer {
            if let previousMode { defaults.set(previousMode, forKey: "workspaceMode") }
            else { defaults.removeObject(forKey: "workspaceMode") }
        }

        let board = Board(name: "Minkops Kanban")
        let task = TaskItem(boardID: board.id, title: "Apply — Acme — Analyst", status: .toDo)
        let role = JobRole(
            track: .backup,
            employer: "Acme",
            role: "Analyst",
            linkedTaskID: task.id
        )
        let snapshot = OwnwardSnapshot(
            boards: [board],
            tasks: [task],
            jobSearch: JobSearchWorkspace(roles: [role])
        )
        let repository = try WorkspaceRepository(inMemory: snapshot)
        let server = LocalAPIServer(router: APIRouter(repository: repository, token: "test"))
        let model = AppModel(repository: repository, apiServer: server, initialSnapshot: snapshot)

        model.revealLinkedApplicationTask(for: role)

        #expect(model.workspaceMode == .projectManagement)
        #expect(model.sidebarSelection == .board(board.id))
        #expect(model.selectedTaskID == task.id)
    }

    @Test("project filter commands replace the observable filter value")
    @MainActor
    func projectFilterCommands() throws {
        let board = Board(name: "Minkops Kanban")
        let todo = TaskItem(boardID: board.id, title: "Plan", status: .toDo, team: "Product")
        let active = TaskItem(boardID: board.id, title: "Build", status: .inProgress, team: "Engineering")
        let snapshot = OwnwardSnapshot(boards: [board], tasks: [todo, active])
        let repository = try WorkspaceRepository(inMemory: snapshot)
        let server = LocalAPIServer(router: APIRouter(repository: repository, token: "test"))
        let model = AppModel(repository: repository, apiServer: server, initialSnapshot: snapshot)

        model.setProjectStatusFilter(.inProgress)
        #expect(model.projectTaskFilter.status == .inProgress)
        #expect(model.visibleTasks.map(\.id) == [active.id])

        model.setProjectTeamFilter(.named("Product"))
        #expect(model.projectTaskFilter.team == .named("Product"))
        #expect(model.visibleTasks.isEmpty)

        model.setProjectStatusFilter(nil)
        #expect(model.visibleTasks.map(\.id) == [todo.id])
    }

    @Test("role list progressively reveals columns instead of overflowing")
    func adaptiveLayoutClasses() {
        #expect(JobSearchLayoutPolicy.layout(for: 420) == .compact)
        #expect(JobSearchLayoutPolicy.layout(for: 619) == .compact)
        #expect(JobSearchLayoutPolicy.layout(for: 620) == .regular)
        #expect(JobSearchLayoutPolicy.layout(for: 899) == .regular)
        #expect(JobSearchLayoutPolicy.layout(for: 900) == .wide)
    }

    @Test("the full-width content plus inspector fits inside Ownward's minimum window")
    func minimumWindowComposition() {
        let contentWidth = JobSearchLayoutPolicy.availableListWidth(
            windowWidth: 987,
            sidebarWidth: 215,
            inspectorWidth: 320
        )

        #expect(contentWidth == 452)
        #expect(JobSearchLayoutPolicy.layout(for: contentWidth) == .compact)
    }

    @Test("regular and wide job tables keep location in the primary list")
    func locationColumnPolicy() {
        #expect(JobSearchLayoutPolicy.columns(for: .regular) == [.opportunity, .location, .stage, .nextDate])
        #expect(JobSearchLayoutPolicy.columns(for: .wide) == [.opportunity, .location, .stage, .track, .nextDate])
    }

    @Test("resume resolution prefers an exact recorded TeX source or its PDF sibling")
    func resolvesRecordedResumeSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdf = directory.appendingPathComponent("Kartik_Example_Data_Analyst.pdf")
        let tex = directory.appendingPathComponent("Kartik_Example_Data_Analyst.tex")
        try Data().write(to: pdf)
        try Data().write(to: tex)

        #expect(JobResumeSourceLocator.resolve(recordedPath: tex.path, employer: "Example", role: "Data Analyst") == tex)
        #expect(JobResumeSourceLocator.resolve(recordedPath: pdf.path, employer: "Example", role: "Data Analyst") == tex)
    }

    @Test("resume fallback requires one strong unambiguous TeX match")
    func resolvesUniqueFallbackOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let match = root.appendingPathComponent("KARTIK_KUMAR_WESWAY_DATA_SPECIALIST.tex")
        let unrelated = root.appendingPathComponent("KARTIK_KUMAR_BRIGHTISLE_BI_ANALYST.tex")
        try Data().write(to: match)
        try Data().write(to: unrelated)

        #expect(JobResumeSourceLocator.resolve(
            recordedPath: "",
            employer: "Wesway",
            role: "Data Specialist",
            searchRoot: root
        ) == match)

        let secondMatch = root.appendingPathComponent("WESWAY_DATA_SPECIALIST_FINAL.tex")
        try Data().write(to: secondMatch)
        #expect(JobResumeSourceLocator.resolve(
            recordedPath: "",
            employer: "Wesway",
            role: "Data Specialist",
            searchRoot: root
        ) == nil)
    }
}
