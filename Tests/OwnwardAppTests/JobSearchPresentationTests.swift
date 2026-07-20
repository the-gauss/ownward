import Foundation
import Testing
@testable import OwnwardApp
@testable import OwnwardCore
@testable import OwnwardServices

@Suite("Job Search presentation policy")
struct JobSearchPresentationTests {
    @Test("scheduled log markdown keeps blocks separate and finds checklist markers after list prefixes")
    func scheduledLogMarkdownDocument() throws {
        let markdown = """
        ## Today *and tomorrow*

        A short paragraph with **emphasis** and a [reference](https://example.com).

        - **08:00** — [ ] Review the design notes.
          - [x] Keep the accepted constraints.
        1. Preserve this ordered step.

        > Keep this quoted reminder.

        ---

        ```swift
        let delivered = true
        ```
        """

        let document = ScheduledLogMarkdownDocument(markdown: markdown)

        #expect(document.blocks.contains { block in
            if case let .heading(_, level, content) = block {
                return level == 2 && content == "Today *and tomorrow*"
            }
            return false
        })
        #expect(document.blocks.contains { block in
            if case let .paragraph(_, content) = block {
                return content.contains("**emphasis**") && content.contains("[reference](https://example.com)")
            }
            return false
        })
        #expect(document.blocks.contains { block in
            if case let .orderedListItem(_, _, marker, content) = block {
                return marker == "1." && content == "Preserve this ordered step."
            }
            return false
        })
        #expect(document.blocks.contains { block in
            if case let .quote(_, content) = block {
                return content == "Keep this quoted reminder."
            }
            return false
        })
        #expect(document.blocks.contains { block in
            if case let .codeBlock(_, language, code) = block {
                return language == "swift" && code == "let delivered = true"
            }
            return false
        })
        #expect(document.blocks.contains { if case .divider = $0 { return true }; return false })
        #expect(document.checklistItems.map(\.isCompleted) == [false, true])
        #expect(document.checklistItems.map(\.depth) == [0, 1])

        let toggledMarkdown = try #require(document.togglingChecklist(at: document.checklistItems[0].id))
        let toggled = ScheduledLogMarkdownDocument(markdown: toggledMarkdown)
        #expect(toggled.checklistItems.map(\.isCompleted) == [true, true])
        #expect(toggledMarkdown.contains("**08:00** — [x] Review the design notes."))
    }

    @Test("scheduled log Markdown tables render as rows and keep table checkboxes interactive")
    func scheduledLogMarkdownTableDocument() throws {
        let markdown = """
        ## Today

        | Time | Action | Source | Budget |
        | --- | --- | --- | --- |
        | 4:30–6:00 AM | - [ ] Review the design notes. | Minkops Kanban | 90 minutes |
        | 6:30–8:00 AM | - [x] Record the solution pattern. | Myndral Kanban | 90 minutes |
        """

        let document = ScheduledLogMarkdownDocument(markdown: markdown)

        let table = try #require(document.tables.first)
        #expect(table.headers == ["Time", "Action", "Source", "Budget"])
        #expect(table.rows.map(\.cells) == [
            ["4:30–6:00 AM", "- [ ] Review the design notes.", "Minkops Kanban", "90 minutes"],
            ["6:30–8:00 AM", "- [x] Record the solution pattern.", "Myndral Kanban", "90 minutes"],
        ])
        #expect(document.checklistItems.map(\.isCompleted) == [false, true])

        let toggledMarkdown = try #require(document.togglingChecklist(at: document.checklistItems[0].id))
        let toggled = ScheduledLogMarkdownDocument(markdown: toggledMarkdown)
        #expect(toggled.checklistItems.map(\.isCompleted) == [true, true])
        #expect(toggledMarkdown.contains("| 4:30–6:00 AM | - [x] Review the design notes."))
    }

    @Test("scheduled log checkbox updates only its persisted markdown marker")
    @MainActor
    func scheduledLogChecklistPersistence() async throws {
        let entry = ScheduledLogEntry(
            kind: .weeklyCanadaRolesSearch,
            markdown: "- [ ] Follow up with the hiring team.\n- [x] Preserve this completed item."
        )
        let unrelated = ScheduledLogEntry(kind: .dailyDayStarter, markdown: "# Leave this daily log alone")
        let snapshot = OwnwardSnapshot(scheduledLogs: [entry, unrelated])
        let repository = try WorkspaceRepository(inMemory: snapshot)
        let server = LocalAPIServer(router: APIRouter(repository: repository, token: "test"))
        let model = AppModel(repository: repository, apiServer: server, initialSnapshot: snapshot)

        model.toggleScheduledLogChecklist(entryID: entry.id, checklistID: 0)

        for _ in 0..<100 {
            let updated = await repository.snapshot()
            if updated.scheduledLogs.first(where: { $0.id == entry.id })?.markdown.contains("- [x] Follow up with the hiring team.") == true {
                #expect(updated.scheduledLogs.first(where: { $0.id == unrelated.id }) == unrelated)
                return
            }
            await Task.yield()
        }

        Issue.record("The scheduled-log checkbox mutation did not persist.")
    }

    @Test("project task commands are unavailable in Job Search mode")
    func workspaceCommandScope() {
        #expect(WorkspaceMode.projectManagement.supportsProjectControls)
        #expect(!WorkspaceMode.jobSearch.supportsProjectControls)
        #expect(JobSearchSidebarSelection.contactsDirectory.title == "Contacts Directory")
    }

    @Test("contact directory routes produce usable mail phone and public-source destinations")
    func contactDirectoryRoutes() {
        #expect(JobSearchContactRoutes.mailtoURL(for: "  avery+jobs@example.ca ")?.absoluteString == "mailto:avery+jobs@example.ca")
        #expect(JobSearchContactRoutes.phoneURL(for: "+1 (807) 555-0100")?.absoluteString == "tel:+18075550100")
        #expect(JobSearchContactRoutes.publicSourceURL(for: "https://example.ca/careers")?.absoluteString == "https://example.ca/careers")
        #expect(JobSearchContactRoutes.publicSourceURL(for: "mailto:jobs@example.ca") == nil)
        #expect(JobSearchContactRoutes.publicSourceURL(for: "not a URL") == nil)
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
