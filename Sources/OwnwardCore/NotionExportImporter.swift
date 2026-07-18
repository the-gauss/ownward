import Foundation

public enum NotionExportImporter {
    public static func `import`(data: Data) throws -> OwnwardSnapshot {
        let raw = try JSONDecoder().decode(RawExport.self, from: data)
        guard let boardUUID = UUID(uuidString: raw.board.id) else { throw ImportError.invalidBoardID }
        let boardID = BoardID(rawValue: boardUUID)
        let board = Board(id: boardID, name: raw.board.name, teams: raw.board.workstreams, externalID: raw.board.id)
        let tasks = raw.tasks.enumerated().compactMap { taskOrder, row -> TaskItem? in
            guard let taskUUID = notionUUID(from: row.url) else { return nil }
            let taskID = TaskID(rawValue: taskUUID)
            let content = pageContent(in: row.pageText)
            let combined = [row.description, content].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
            let parsed = MarkdownChecklistParser.parse(combined, taskID: taskID)
            let timestamp = pageTimestamp(in: row.pageText) ?? Date()
            return TaskItem(
                id: taskID,
                boardID: boardID,
                title: row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : row.name,
                status: TaskStatus(notionName: row.status),
                previousActiveStatus: TaskStatus(notionName: row.status).isComplete ? .toDo : TaskStatus(notionName: row.status),
                team: row.team,
                deadlineStart: notionDate(row.deadlineStart),
                deadlineEnd: notionDate(row.deadlineEnd),
                notesMarkdown: parsed.notesMarkdown,
                links: parsed.links,
                miniTasks: parsed.miniTasks,
                manualOrder: taskOrder,
                externalID: row.url,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
        return OwnwardSnapshot(schemaVersion: 2, boards: [board], tasks: tasks)
    }

    public static func merge(_ snapshots: [OwnwardSnapshot]) -> OwnwardSnapshot {
        OwnwardSnapshot(
            schemaVersion: snapshots.map(\.schemaVersion).max() ?? 1,
            boards: snapshots.flatMap(\.boards).uniqued(on: \.id),
            tasks: snapshots.flatMap(\.tasks).uniqued(on: \.id),
            referenceGroups: snapshots.flatMap(\.referenceGroups)
        )
    }

    private static func pageContent(in pageText: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<content>\s*(.*?)\s*</content>"#, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: pageText, range: NSRange(pageText.startIndex..<pageText.endIndex, in: pageText)),
              let range = Range(match.range(at: 1), in: pageText) else { return "" }
        return String(pageText[range])
    }

    private static func pageTimestamp(in pageText: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"as of ([0-9T:.+-]+Z)"#),
              let match = regex.firstMatch(in: pageText, range: NSRange(pageText.startIndex..<pageText.endIndex, in: pageText)),
              let range = Range(match.range(at: 1), in: pageText) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: String(pageText[range]))
    }

    private static func notionDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func notionUUID(from url: String) -> UUID? {
        let compact = url.split(separator: "/").last.map(String.init) ?? url
        guard compact.count >= 32 else { return UUID(uuidString: compact) }
        let hex = String(compact.suffix(32))
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: formatted)
    }
}

public enum ImportError: Error { case invalidBoardID }

private struct RawExport: Decodable {
    var board: RawBoard
    var tasks: [RawTask]
}

private struct RawBoard: Decodable {
    var id: String
    var name: String
    var workstreams: [String]
}

private struct RawTask: Decodable {
    var name: String
    var status: String
    var team: String?
    var deadlineStart: String?
    var deadlineEnd: String?
    var description: String
    var url: String
    var pageText: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case status = "Status"
        case team = "Team"
        case deadlineStart = "date:Deadline:start"
        case deadlineEnd = "date:Deadline:end"
        case description = "Description"
        case url
        case pageText
    }
}

private extension TaskStatus {
    init(notionName: String) {
        switch notionName {
        case "In Progress": self = .inProgress
        case "Paused": self = .paused
        case "Done": self = .done
        case "Discarded": self = .discarded
        default: self = .toDo
        }
    }
}

private extension Array {
    func uniqued<Key: Hashable>(on keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
