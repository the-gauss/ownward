import Foundation
import Testing
@testable import OwnwardCore

@Suite("Notion export import")
struct NotionExportImporterTests {
    @Test("imports only used fields and promotes page checklists")
    func importsPage() throws {
        let json = #"""
        {
          "board": {
            "id": "90f0f431-89ea-83dc-a148-87895e93e853",
            "name": "Minkops Kanban",
            "workstreams": ["Interview Prep"]
          },
          "tasks": [{
            "Name": "System Design",
            "Status": "In Progress",
            "Team": "Interview Prep",
            "date:Deadline:start": "2026-07-17",
            "date:Deadline:end": "2026-08-05",
            "Description": "",
            "url": "https://app.notion.com/p/29c0f43189ea83398c1c014a69288990",
            "pageText": "<page><content>## Plan\n- [x] Requirements\n- [ ] API design\n[Primer](https://example.com)</content></page>"
          }]
        }
        """#

        let snapshot = try NotionExportImporter.import(data: Data(json.utf8))

        #expect(snapshot.boards[0].name == "Minkops Kanban")
        #expect(snapshot.tasks[0].status == .inProgress)
        #expect(snapshot.tasks[0].workstream == "Interview Prep")
        #expect(snapshot.tasks[0].miniTasks.map(\.title) == ["Requirements", "API design"])
        #expect(snapshot.tasks[0].miniTasks.map(\.category) == ["Plan", "Plan"])
        #expect(snapshot.tasks[0].links.map(\.title) == ["Primer"])
        #expect(!snapshot.tasks[0].notesMarkdown.contains("## Plan"))
    }
}
