import Foundation
import Testing
@testable import OwnwardCore

@Suite("Snapshot persistence")
struct SnapshotPersistenceTests {
    @Test("snapshot round-trips without losing reference metadata")
    func roundTrip() throws {
        let board = Board(name: "Minkops Kanban")
        var task = TaskItem(boardID: board.id, title: "System Design", status: .inProgress)
        task.miniTasks = [MiniTask(taskID: task.id, title: "API design")]
        let snapshot = OwnwardSnapshot(
            boards: [board],
            tasks: [task],
            referenceGroups: [.init(members: [.task(task.id), .miniTask(task.miniTasks[0].id)])]
        )

        let data = try JSONEncoder.ownward.encode(snapshot)
        let decoded = try JSONDecoder.ownward.decode(OwnwardSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test("snapshot round-trips the durable job-search workspace")
    func jobSearchRoundTrip() throws {
        let role = JobRole(
            track: .backup,
            employer: "Wesway",
            role: "Data Specialist",
            posting: JobPosting(jobURL: "https://example.ca/role"),
            application: JobApplication(applied: true, notes: "User-owned history")
        )
        let snapshot = OwnwardSnapshot(
            schemaVersion: SnapshotMigrator.currentSchemaVersion,
            jobSearch: JobSearchWorkspace(
                roles: [role],
                activities: [JobActivity(roleID: role.id, kind: .created, detail: "Imported once")]
            )
        )

        let decoded = try JSONDecoder.ownward.decode(
            OwnwardSnapshot.self,
            from: JSONEncoder.ownward.encode(snapshot)
        )

        #expect(decoded == snapshot)
    }

    @Test("pre-job-search snapshots decode with an empty durable workspace")
    func legacySnapshotDefaultsJobSearch() throws {
        let legacy = Data("{\"schemaVersion\":3,\"boards\":[],\"tasks\":[],\"referenceGroups\":[]}".utf8)

        let decoded = try JSONDecoder.ownward.decode(OwnwardSnapshot.self, from: legacy)

        #expect(decoded.jobSearch == .empty)
    }

    @Test("migration repairs the malformed activity text from the first job-search import")
    func repairsImportedActivityText() {
        let role = JobRole(track: .canon, employer: "Acme", role: "Analyst")
        let activity = JobActivity(
            roleID: role.id,
            kind: .created,
            detail: "Verified role added to the (verified.track.title) track."
        )
        let snapshot = OwnwardSnapshot(
            schemaVersion: 4,
            jobSearch: JobSearchWorkspace(roles: [role], activities: [activity])
        )

        let migrated = SnapshotMigrator.upgrade(snapshot)

        #expect(migrated.schemaVersion == 5)
        #expect(migrated.jobSearch.activities[0].detail == "Verified role added to the Canon track.")
    }

    @Test("legacy object identifiers remain readable")
    func legacyIdentifier() throws {
        let data = Data(#"{"rawValue":"90F0F431-89EA-83DC-A148-87895E93E853"}"#.utf8)
        let decoded = try JSONDecoder().decode(BoardID.self, from: data)
        #expect(decoded.description == "90f0f431-89ea-83dc-a148-87895e93e853")
    }

    @Test("migration enriches existing tasks without replacing user state")
    func enrichesFromSeed() {
        let board = Board(name: "Minkops")
        let taskID = TaskID()
        var existing = TaskItem(id: taskID, boardID: board.id, title: "Leetcode DSA", status: .inProgress)
        existing.miniTasks = [MiniTask(taskID: taskID, title: "Palindrome Number", order: 0)]
        existing.notesMarkdown = "Preparation notes.\n## Math\n---"
        var seeded = existing
        seeded.status = .toDo
        seeded.miniTasks[0].category = "Math"

        let migrated = SnapshotMigrator.upgrade(
            OwnwardSnapshot(schemaVersion: 1, boards: [board], tasks: [existing]),
            using: OwnwardSnapshot(schemaVersion: 2, boards: [board], tasks: [seeded])
        )

        #expect(migrated.schemaVersion == SnapshotMigrator.currentSchemaVersion)
        #expect(migrated.tasks[0].status == .inProgress)
        #expect(migrated.tasks[0].miniTasks[0].category == "Math")
        #expect(migrated.tasks[0].manualOrder == 0)
        #expect(migrated.tasks[0].notesMarkdown == "Preparation notes.")
    }

    @Test("workspace remains available to overnight automations after the Mac locks")
    func usesUntilFirstAuthenticationProtection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("workspace.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try WorkspaceRepository(fileURL: fileURL, initialSnapshot: .empty)
        try await repository.replace(with: OwnwardSnapshot(schemaVersion: 2))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
    }
}
