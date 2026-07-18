import Foundation

public protocol OwnwardIdentifier: Codable, Hashable, Sendable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

public extension OwnwardIdentifier {
    init() { self.init(rawValue: UUID()) }
    var description: String { rawValue.uuidString.lowercased() }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value: String
        if let current = try? container.decode(String.self) {
            value = current
        } else {
            value = try container.decode(LegacyIdentifier.self).rawValue
        }
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a UUID string.")
        }
        self.init(rawValue: uuid)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

private struct LegacyIdentifier: Decodable { let rawValue: String }

public struct BoardID: OwnwardIdentifier, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct TaskID: OwnwardIdentifier, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct MiniTaskID: OwnwardIdentifier, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ReferenceGroupID: OwnwardIdentifier, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case toDo = "to_do"
    case inProgress = "in_progress"
    case paused
    case done
    case discarded

    public var title: String {
        switch self {
        case .toDo: "To Do"
        case .inProgress: "In Progress"
        case .paused: "Paused"
        case .done: "Done"
        case .discarded: "Discarded"
        }
    }

    public static let boardColumns: [TaskStatus] = [.toDo, .inProgress, .done]
    public var isComplete: Bool { self == .done }
}

public struct Board: Codable, Equatable, Identifiable, Sendable {
    public var id: BoardID
    public var name: String
    public var workstreams: [String]
    public var externalID: String?

    public init(id: BoardID = BoardID(), name: String, teams: [String] = [], externalID: String? = nil) {
        self.id = id
        self.name = name
        self.workstreams = teams
        self.externalID = externalID
    }

    public var teams: [String] {
        get { workstreams }
        set { workstreams = newValue }
    }

    private enum CodingKeys: String, CodingKey { case id, name, teams, workstreams, externalID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(BoardID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workstreams = try container.decodeIfPresent([String].self, forKey: .teams)
            ?? container.decodeIfPresent([String].self, forKey: .workstreams)
            ?? []
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(workstreams, forKey: .teams)
        try container.encodeIfPresent(externalID, forKey: .externalID)
    }
}

public struct TaskLink: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { url }
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public struct MiniTask: Codable, Equatable, Identifiable, Sendable {
    public var id: MiniTaskID
    public var taskID: TaskID
    public var title: String
    public var isCompleted: Bool
    public var depth: Int
    public var order: Int
    public var category: String?
    public var externalID: String?

    public init(
        id: MiniTaskID = MiniTaskID(),
        taskID: TaskID,
        title: String,
        isCompleted: Bool = false,
        depth: Int = 0,
        order: Int = 0,
        category: String? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.isCompleted = isCompleted
        self.depth = max(0, depth)
        self.order = order
        self.category = category
        self.externalID = externalID
    }
}

public struct TaskItem: Codable, Equatable, Identifiable, Sendable {
    public var id: TaskID
    public var boardID: BoardID
    public var title: String
    public var status: TaskStatus
    public var previousActiveStatus: TaskStatus?
    public var workstream: String?
    public var deadlineStart: Date?
    public var deadlineEnd: Date?
    public var notesMarkdown: String
    public var links: [TaskLink]
    public var miniTasks: [MiniTask]
    public var manualOrder: Int?
    public var externalID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: TaskID = TaskID(),
        boardID: BoardID,
        title: String,
        status: TaskStatus = .toDo,
        previousActiveStatus: TaskStatus? = nil,
        team: String? = nil,
        deadlineStart: Date? = nil,
        deadlineEnd: Date? = nil,
        notesMarkdown: String = "",
        links: [TaskLink] = [],
        miniTasks: [MiniTask] = [],
        manualOrder: Int? = nil,
        externalID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.boardID = boardID
        self.title = title
        self.status = status
        self.previousActiveStatus = previousActiveStatus
        self.workstream = team
        self.deadlineStart = deadlineStart
        self.deadlineEnd = deadlineEnd
        self.notesMarkdown = notesMarkdown
        self.links = links
        self.miniTasks = miniTasks
        self.manualOrder = manualOrder
        self.externalID = externalID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var completedMiniTaskCount: Int { miniTasks.count(where: \.isCompleted) }
    public var checklistProgress: Double {
        miniTasks.isEmpty ? 0 : Double(completedMiniTaskCount) / Double(miniTasks.count)
    }
    public var team: String? {
        get { workstream }
        set { workstream = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id, boardID, title, status, previousActiveStatus, team, workstream
        case deadlineStart, deadlineEnd, notesMarkdown, links, miniTasks, manualOrder
        case externalID, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TaskID.self, forKey: .id)
        boardID = try container.decode(BoardID.self, forKey: .boardID)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(TaskStatus.self, forKey: .status)
        previousActiveStatus = try container.decodeIfPresent(TaskStatus.self, forKey: .previousActiveStatus)
        workstream = try container.decodeIfPresent(String.self, forKey: .team)
            ?? container.decodeIfPresent(String.self, forKey: .workstream)
        deadlineStart = try container.decodeIfPresent(Date.self, forKey: .deadlineStart)
        deadlineEnd = try container.decodeIfPresent(Date.self, forKey: .deadlineEnd)
        notesMarkdown = try container.decodeIfPresent(String.self, forKey: .notesMarkdown) ?? ""
        links = try container.decodeIfPresent([TaskLink].self, forKey: .links) ?? []
        miniTasks = try container.decodeIfPresent([MiniTask].self, forKey: .miniTasks) ?? []
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder)
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(boardID, forKey: .boardID)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(previousActiveStatus, forKey: .previousActiveStatus)
        try container.encodeIfPresent(workstream, forKey: .team)
        try container.encodeIfPresent(deadlineStart, forKey: .deadlineStart)
        try container.encodeIfPresent(deadlineEnd, forKey: .deadlineEnd)
        try container.encode(notesMarkdown, forKey: .notesMarkdown)
        try container.encode(links, forKey: .links)
        try container.encode(miniTasks, forKey: .miniTasks)
        try container.encodeIfPresent(manualOrder, forKey: .manualOrder)
        try container.encodeIfPresent(externalID, forKey: .externalID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum CompletionTarget: Codable, Equatable, Hashable, Sendable {
    case task(TaskID)
    case miniTask(MiniTaskID)

    public var rawID: String {
        switch self {
        case .task(let id): id.description
        case .miniTask(let id): id.description
        }
    }

    public var kind: String {
        switch self {
        case .task: "task"
        case .miniTask: "mini_task"
        }
    }

    private enum CodingKeys: String, CodingKey { case type, id }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .id)
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Expected a UUID string.")
        }
        switch type {
        case "task": self = .task(TaskID(rawValue: uuid))
        case "mini_task": self = .miniTask(MiniTaskID(rawValue: uuid))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown completion target type.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        try container.encode(rawID, forKey: .id)
    }
}

public struct CompletionReferenceGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: ReferenceGroupID
    public var members: Set<CompletionTarget>

    public init(id: ReferenceGroupID = ReferenceGroupID(), members: Set<CompletionTarget>) {
        self.id = id
        self.members = members
    }
}

public struct OwnwardSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var boards: [Board]
    public var tasks: [TaskItem]
    public var referenceGroups: [CompletionReferenceGroup]
    public var jobSearch: JobSearchWorkspace

    public init(
        schemaVersion: Int = 1,
        boards: [Board] = [],
        tasks: [TaskItem] = [],
        referenceGroups: [CompletionReferenceGroup] = [],
        jobSearch: JobSearchWorkspace = .empty
    ) {
        self.schemaVersion = schemaVersion
        self.boards = boards
        self.tasks = tasks
        self.referenceGroups = referenceGroups
        self.jobSearch = jobSearch
    }

    public static let empty = OwnwardSnapshot()

    public func task(id: TaskID) -> TaskItem? { tasks.first { $0.id == id } }
    public func miniTask(id: MiniTaskID) -> MiniTask? {
        tasks.lazy.compactMap { $0.miniTasks.first { $0.id == id } }.first
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, boards, tasks, referenceGroups, jobSearch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        boards = try container.decodeIfPresent([Board].self, forKey: .boards) ?? []
        tasks = try container.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        referenceGroups = try container.decodeIfPresent([CompletionReferenceGroup].self, forKey: .referenceGroups) ?? []
        jobSearch = try container.decodeIfPresent(JobSearchWorkspace.self, forKey: .jobSearch) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(boards, forKey: .boards)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(referenceGroups, forKey: .referenceGroups)
        try container.encode(jobSearch, forKey: .jobSearch)
    }
}

public extension JSONEncoder {
    static var ownward: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate.bitPattern)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var ownward: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let bits = try decoder.singleValueContainer().decode(UInt64.self)
            return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
        }
        return decoder
    }
}
