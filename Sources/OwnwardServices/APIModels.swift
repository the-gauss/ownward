import Foundation
import OwnwardCore

public struct APIRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    public init(
        method: String,
        path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        self.method = method.uppercased()
        self.path = path
        self.query = query
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }
}

public struct APIResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = ["content-type": "application/json; charset=utf-8"], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> APIResponse {
        do { return APIResponse(status: status, body: try JSONEncoder.api.encode(value)) }
        catch { return .error(status: 500, message: "Response encoding failed.") }
    }

    public static func error(status: Int, message: String) -> APIResponse {
        .json(APIErrorBody(error: message), status: status)
    }
}

public struct APIErrorBody: Codable, Sendable { public var error: String }

public struct DayStarterContext: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var boards: [Board]
    public var tasks: [TaskItem]
    public var referenceGroups: [CompletionReferenceGroup]

    public init(generatedAt: Date = Date(), boards: [Board], tasks: [TaskItem], referenceGroups: [CompletionReferenceGroup] = []) {
        self.generatedAt = generatedAt
        self.boards = boards
        self.tasks = tasks
        self.referenceGroups = referenceGroups
    }
}

public struct CreateTaskRequest: Codable, Sendable {
    public var boardID: BoardID
    public var title: String
    public var status: TaskStatus?
    public var workstream: String?
    public var team: String?
    public var deadlineStart: Date?
    public var deadlineEnd: Date?
    public var notesMarkdown: String?

    public init(boardID: BoardID, title: String, status: TaskStatus? = nil, team: String? = nil, deadlineStart: Date? = nil, deadlineEnd: Date? = nil, notesMarkdown: String? = nil) {
        self.boardID = boardID
        self.title = title
        self.status = status
        self.workstream = nil
        self.team = team
        self.deadlineStart = deadlineStart
        self.deadlineEnd = deadlineEnd
        self.notesMarkdown = notesMarkdown
    }
}

public struct UpdateTaskRequest: Codable, Sendable {
    public var title: String?
    public var status: TaskStatus?
    public var workstream: String?
    public var team: String?
    public var deadlineStart: Date?
    public var deadlineEnd: Date?
    public var notesMarkdown: String?
    public var links: [TaskLink]?
}

public struct MoveTaskRequest: Codable, Sendable {
    public var status: TaskStatus
    public var team: String?
    public var beforeTaskID: TaskID?

    public init(status: TaskStatus, team: String? = nil, beforeTaskID: TaskID? = nil) {
        self.status = status
        self.team = team
        self.beforeTaskID = beforeTaskID
    }
}

public struct ShiftTaskScheduleRequest: Codable, Sendable {
    public var days: Int

    public init(days: Int) { self.days = days }
}

public struct ResizeTaskScheduleRequest: Codable, Sendable {
    public var edge: TimelineEdge
    public var date: Date

    public init(edge: TimelineEdge, date: Date) {
        self.edge = edge
        self.date = date
    }
}

public struct CreateMiniTaskRequest: Codable, Sendable {
    public var title: String
    public var isCompleted: Bool?
    public var depth: Int?
    public var category: String?
}

public struct UpdateMiniTaskRequest: Codable, Sendable {
    public var title: String?
    public var isCompleted: Bool?
    public var depth: Int?
    public var category: String?
}

public struct CreateBoardRequest: Codable, Sendable {
    public var name: String

    public init(name: String) { self.name = name }
}

public struct SetCompletionRequest: Codable, Sendable {
    public var target: APITarget
    public var complete: Bool
}

public struct CreateReferenceRequest: Codable, Sendable {
    public var source: APITarget
    public var target: APITarget
}

public struct APITarget: Codable, Sendable {
    public var type: String
    public var id: String

    public func completionTarget() throws -> CompletionTarget {
        guard let uuid = UUID(uuidString: id) else { throw DomainError.targetNotFound }
        switch type {
        case "task": return .task(TaskID(rawValue: uuid))
        case "mini_task": return .miniTask(MiniTaskID(rawValue: uuid))
        default: throw DomainError.targetNotFound
        }
    }
}

public struct ReferenceResponse: Codable, Sendable {
    public var groups: [CompletionReferenceGroup]
}

public struct HealthResponse: Codable, Sendable {
    public var status: String = "ok"
    public var apiVersion: String = "v1"
}

public extension JSONEncoder {
    static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: value) { return date }
            let dateOnly = DateFormatter()
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.calendar = Calendar(identifier: .gregorian)
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Expected an ISO-8601 date.")
        }
        return decoder
    }
}
