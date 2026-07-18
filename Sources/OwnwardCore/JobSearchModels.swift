import Foundation

public struct JobRoleID: OwnwardIdentifier, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct JobActivityID: OwnwardIdentifier, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum JobSearchTrack: String, Codable, CaseIterable, Identifiable, Sendable {
    case backup
    case canon
    case backupExtreme = "backup_extreme"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .backup: "Backup"
        case .canon: "Canon"
        case .backupExtreme: "Backup Extreme"
        }
    }
}

public enum JobStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case researching
    case readyToApply = "ready_to_apply"
    case applied
    case interviewing
    case offer
    case rejected
    case closed
    case archived

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .researching: "Researching"
        case .readyToApply: "Ready to Apply"
        case .applied: "Applied"
        case .interviewing: "Interviewing"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .closed: "Closed"
        case .archived: "Archived"
        }
    }

    public var isTerminal: Bool { [.rejected, .closed, .archived].contains(self) }
    public var isApplicationStage: Bool { [.applied, .interviewing, .offer, .rejected].contains(self) }
}

public enum JobSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case needsAction
    case applications
    case interviews
    case followUps
    case closed
    case archive

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "All Opportunities"
        case .needsAction: "Needs Action"
        case .applications: "Applications"
        case .interviews: "Interviews"
        case .followUps: "Follow-ups"
        case .closed: "Closed"
        case .archive: "Archive"
        }
    }
}

public enum JobSearchSort: String, CaseIterable, Identifiable, Sendable {
    case nextAction
    case recentlyUpdated
    case employer
    case priority

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .nextAction: "Next Date"
        case .recentlyUpdated: "Recently Updated"
        case .employer: "Employer"
        case .priority: "Priority"
        }
    }
}

public enum JobNextActionKind: Equatable, Sendable {
    case deadline
    case followUp
}

public struct JobNextAction: Equatable, Sendable {
    public var kind: JobNextActionKind
    public var date: Date

    public init(kind: JobNextActionKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

public struct JobLocation: Codable, Equatable, Sendable {
    public var city: String
    public var province: String
    public var workArrangement: String

    public init(city: String = "", province: String = "", workArrangement: String = "") {
        self.city = city
        self.province = province
        self.workArrangement = workArrangement
    }

    public var displayName: String {
        [city, province].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")
    }
}

public struct JobPosting: Codable, Equatable, Sendable {
    public var status: String
    public var verificationTier: String
    public var jobURL: String
    public var officialCareersURL: String
    public var postedDate: Date?
    public var deadlineDate: Date?
    public var deadlineNotes: String
    public var lastVerified: Date?

    public init(
        status: String = "",
        verificationTier: String = "",
        jobURL: String = "",
        officialCareersURL: String = "",
        postedDate: Date? = nil,
        deadlineDate: Date? = nil,
        deadlineNotes: String = "",
        lastVerified: Date? = nil
    ) {
        self.status = status
        self.verificationTier = verificationTier
        self.jobURL = jobURL
        self.officialCareersURL = officialCareersURL
        self.postedDate = postedDate
        self.deadlineDate = deadlineDate
        self.deadlineNotes = deadlineNotes
        self.lastVerified = lastVerified
    }
}

public struct JobPositionDetails: Codable, Equatable, Sendable {
    public var compensation: String
    public var employmentType: String
    public var experienceRequirement: String
    public var relevantSkills: String

    public init(
        compensation: String = "",
        employmentType: String = "",
        experienceRequirement: String = "",
        relevantSkills: String = ""
    ) {
        self.compensation = compensation
        self.employmentType = employmentType
        self.experienceRequirement = experienceRequirement
        self.relevantSkills = relevantSkills
    }
}

public struct JobContact: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var titleOrDepartment: String
    public var email: String
    public var phone: String
    public var sourceURL: String
    public var confidence: String
    public var isPrimary: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        titleOrDepartment: String = "",
        email: String = "",
        phone: String = "",
        sourceURL: String = "",
        confidence: String = "",
        isPrimary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.titleOrDepartment = titleOrDepartment
        self.email = email
        self.phone = phone
        self.sourceURL = sourceURL
        self.confidence = confidence
        self.isPrimary = isPrimary
    }

    public var hasRoute: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct JobOutreach: Codable, Equatable, Sendable {
    public var bestChannel: String
    public var suggestedAngle: String
    public var confidence: String

    public init(bestChannel: String = "", suggestedAngle: String = "", confidence: String = "") {
        self.bestChannel = bestChannel
        self.suggestedAngle = suggestedAngle
        self.confidence = confidence
    }
}

public struct JobApplication: Codable, Equatable, Sendable {
    public var applied: Bool
    public var dateApplied: Date?
    public var contacted: Bool
    public var followUpDate: Date?
    public var response: String
    public var notes: String
    public var lastMailChecked: Date?

    public init(
        applied: Bool = false,
        dateApplied: Date? = nil,
        contacted: Bool = false,
        followUpDate: Date? = nil,
        response: String = "",
        notes: String = "",
        lastMailChecked: Date? = nil
    ) {
        self.applied = applied
        self.dateApplied = dateApplied
        self.contacted = contacted
        self.followUpDate = followUpDate
        self.response = response
        self.notes = notes
        self.lastMailChecked = lastMailChecked
    }
}

/// Resume metadata remains automation data. The visible product deliberately
/// exposes only the action that reveals the recorded TeX source in Finder.
public struct JobResume: Codable, Equatable, Sendable {
    public var sourcePath: String
    public var factCheckStatus: String
    public var lastReviewed: Date?

    public init(sourcePath: String = "", factCheckStatus: String = "", lastReviewed: Date? = nil) {
        self.sourcePath = sourcePath
        self.factCheckStatus = factCheckStatus
        self.lastReviewed = lastReviewed
    }
}

public struct JobEvidence: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String
    public var note: String

    public init(id: UUID = UUID(), title: String, url: String, note: String = "") {
        self.id = id
        self.title = title
        self.url = url
        self.note = note
    }
}

public enum JobActivityKind: String, Codable, Equatable, Sendable {
    case created
    case refreshed
    case updated
    case stageChanged = "stage_changed"
    case applicationUpdated = "application_updated"
    case mailboxUpdated = "mailbox_updated"
    case linkedTaskUpdated = "linked_task_updated"
    case resumeUpdated = "resume_updated"
}

public struct JobActivity: Codable, Equatable, Identifiable, Sendable {
    public var id: JobActivityID
    public var roleID: JobRoleID?
    public var date: Date
    public var kind: JobActivityKind
    public var detail: String

    public init(
        id: JobActivityID = JobActivityID(),
        roleID: JobRoleID? = nil,
        date: Date = Date(),
        kind: JobActivityKind,
        detail: String = ""
    ) {
        self.id = id
        self.roleID = roleID
        self.date = date
        self.kind = kind
        self.detail = detail
    }
}

public struct JobRole: Codable, Equatable, Identifiable, Sendable {
    public var id: JobRoleID
    public var track: JobSearchTrack
    public var priority: Int?
    public var employer: String
    public var role: String
    public var location: JobLocation
    public var posting: JobPosting
    public var position: JobPositionDetails
    public var contacts: [JobContact]
    public var outreach: JobOutreach
    public var application: JobApplication
    public var resume: JobResume
    public var evidence: [JobEvidence]
    public var stage: JobStage
    public var linkedTaskID: TaskID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: JobRoleID = JobRoleID(),
        track: JobSearchTrack,
        priority: Int? = nil,
        employer: String,
        role: String,
        location: JobLocation = JobLocation(),
        posting: JobPosting = JobPosting(),
        position: JobPositionDetails = JobPositionDetails(),
        contacts: [JobContact] = [],
        outreach: JobOutreach = JobOutreach(),
        application: JobApplication = JobApplication(),
        resume: JobResume = JobResume(),
        evidence: [JobEvidence] = [],
        stage: JobStage = .researching,
        linkedTaskID: TaskID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.track = track
        self.priority = priority
        self.employer = employer
        self.role = role
        self.location = location
        self.posting = posting
        self.position = position
        self.contacts = contacts
        self.outreach = outreach
        self.application = application
        self.resume = resume
        self.evidence = evidence
        self.stage = stage
        self.linkedTaskID = linkedTaskID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var identity: JobRoleIdentity { JobRoleIdentity(role: self) }
}

public struct JobRoleIdentity: Equatable, Hashable, Sendable {
    public var canonicalURL: String
    public var fallback: String

    public init(role: JobRole) {
        canonicalURL = Self.canonicalURL(role.posting.jobURL)
        fallback = Self.normalize([
            role.employer,
            role.role,
            role.location.city,
            role.location.province,
        ].joined(separator: "|"))
    }

    public func matches(_ other: JobRoleIdentity) -> Bool {
        (!canonicalURL.isEmpty && canonicalURL == other.canonicalURL) || fallback == other.fallback
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func canonicalURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return "" }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        var result = components.string ?? trimmed
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

public struct JobSearchWorkspace: Codable, Equatable, Sendable {
    public var roles: [JobRole]
    public var activities: [JobActivity]

    public init(roles: [JobRole] = [], activities: [JobActivity] = []) {
        self.roles = roles
        self.activities = activities
    }

    public static let empty = JobSearchWorkspace()

    public func role(id: JobRoleID) -> JobRole? { roles.first { $0.id == id } }
}

public enum PatchValue<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case value(Value)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .null : .value(try container.decode(Value.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct JobLocationPatch: Codable, Equatable, Sendable {
    public var city: String?
    public var province: String?
    public var workArrangement: String?

    public init(city: String? = nil, province: String? = nil, workArrangement: String? = nil) {
        self.city = city
        self.province = province
        self.workArrangement = workArrangement
    }
}

public struct JobPostingPatch: Codable, Equatable, Sendable {
    public var status: String?
    public var verificationTier: String?
    public var jobURL: String?
    public var officialCareersURL: String?
    public var postedDate: PatchValue<Date>?
    public var deadlineDate: PatchValue<Date>?
    public var deadlineNotes: String?
    public var lastVerified: PatchValue<Date>?

    public init(
        status: String? = nil,
        verificationTier: String? = nil,
        jobURL: String? = nil,
        officialCareersURL: String? = nil,
        postedDate: PatchValue<Date>? = nil,
        deadlineDate: PatchValue<Date>? = nil,
        deadlineNotes: String? = nil,
        lastVerified: PatchValue<Date>? = nil
    ) {
        self.status = status
        self.verificationTier = verificationTier
        self.jobURL = jobURL
        self.officialCareersURL = officialCareersURL
        self.postedDate = postedDate
        self.deadlineDate = deadlineDate
        self.deadlineNotes = deadlineNotes
        self.lastVerified = lastVerified
    }

    private enum CodingKeys: String, CodingKey {
        case status, verificationTier, jobURL, officialCareersURL
        case postedDate, deadlineDate, deadlineNotes, lastVerified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        verificationTier = try container.decodeIfPresent(String.self, forKey: .verificationTier)
        jobURL = try container.decodeIfPresent(String.self, forKey: .jobURL)
        officialCareersURL = try container.decodeIfPresent(String.self, forKey: .officialCareersURL)
        postedDate = try container.decodePatch(Date.self, forKey: .postedDate)
        deadlineDate = try container.decodePatch(Date.self, forKey: .deadlineDate)
        deadlineNotes = try container.decodeIfPresent(String.self, forKey: .deadlineNotes)
        lastVerified = try container.decodePatch(Date.self, forKey: .lastVerified)
    }
}

public struct JobPositionPatch: Codable, Equatable, Sendable {
    public var compensation: String?
    public var employmentType: String?
    public var experienceRequirement: String?
    public var relevantSkills: String?

    public init(
        compensation: String? = nil,
        employmentType: String? = nil,
        experienceRequirement: String? = nil,
        relevantSkills: String? = nil
    ) {
        self.compensation = compensation
        self.employmentType = employmentType
        self.experienceRequirement = experienceRequirement
        self.relevantSkills = relevantSkills
    }
}

public struct JobOutreachPatch: Codable, Equatable, Sendable {
    public var bestChannel: String?
    public var suggestedAngle: String?
    public var confidence: String?

    public init(bestChannel: String? = nil, suggestedAngle: String? = nil, confidence: String? = nil) {
        self.bestChannel = bestChannel
        self.suggestedAngle = suggestedAngle
        self.confidence = confidence
    }
}

public struct JobApplicationPatch: Codable, Equatable, Sendable {
    public var applied: Bool?
    public var dateApplied: PatchValue<Date>?
    public var contacted: Bool?
    public var followUpDate: PatchValue<Date>?
    public var response: String?
    public var notes: String?
    public var lastMailChecked: PatchValue<Date>?

    public init(
        applied: Bool? = nil,
        dateApplied: PatchValue<Date>? = nil,
        contacted: Bool? = nil,
        followUpDate: PatchValue<Date>? = nil,
        response: String? = nil,
        notes: String? = nil,
        lastMailChecked: PatchValue<Date>? = nil
    ) {
        self.applied = applied
        self.dateApplied = dateApplied
        self.contacted = contacted
        self.followUpDate = followUpDate
        self.response = response
        self.notes = notes
        self.lastMailChecked = lastMailChecked
    }

    private enum CodingKeys: String, CodingKey {
        case applied, dateApplied, contacted, followUpDate, response, notes, lastMailChecked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applied = try container.decodeIfPresent(Bool.self, forKey: .applied)
        dateApplied = try container.decodePatch(Date.self, forKey: .dateApplied)
        contacted = try container.decodeIfPresent(Bool.self, forKey: .contacted)
        followUpDate = try container.decodePatch(Date.self, forKey: .followUpDate)
        response = try container.decodeIfPresent(String.self, forKey: .response)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        lastMailChecked = try container.decodePatch(Date.self, forKey: .lastMailChecked)
    }
}

public struct JobResumePatch: Codable, Equatable, Sendable {
    public var sourcePath: String?
    public var factCheckStatus: String?
    public var lastReviewed: PatchValue<Date>?

    public init(
        sourcePath: String? = nil,
        factCheckStatus: String? = nil,
        lastReviewed: PatchValue<Date>? = nil
    ) {
        self.sourcePath = sourcePath
        self.factCheckStatus = factCheckStatus
        self.lastReviewed = lastReviewed
    }

    private enum CodingKeys: String, CodingKey { case sourcePath, factCheckStatus, lastReviewed }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        factCheckStatus = try container.decodeIfPresent(String.self, forKey: .factCheckStatus)
        lastReviewed = try container.decodePatch(Date.self, forKey: .lastReviewed)
    }
}

public struct JobRolePatch: Codable, Equatable, Sendable {
    public var track: JobSearchTrack?
    public var priority: PatchValue<Int>?
    public var employer: String?
    public var role: String?
    public var location: JobLocationPatch?
    public var posting: JobPostingPatch?
    public var position: JobPositionPatch?
    public var contacts: [JobContact]?
    public var outreach: JobOutreachPatch?
    public var application: JobApplicationPatch?
    public var resume: JobResumePatch?
    public var evidence: [JobEvidence]?
    public var stage: JobStage?
    public var linkedTaskID: PatchValue<TaskID>?

    public init(
        track: JobSearchTrack? = nil,
        priority: PatchValue<Int>? = nil,
        employer: String? = nil,
        role: String? = nil,
        location: JobLocationPatch? = nil,
        posting: JobPostingPatch? = nil,
        position: JobPositionPatch? = nil,
        contacts: [JobContact]? = nil,
        outreach: JobOutreachPatch? = nil,
        application: JobApplicationPatch? = nil,
        resume: JobResumePatch? = nil,
        evidence: [JobEvidence]? = nil,
        stage: JobStage? = nil,
        linkedTaskID: PatchValue<TaskID>? = nil
    ) {
        self.track = track
        self.priority = priority
        self.employer = employer
        self.role = role
        self.location = location
        self.posting = posting
        self.position = position
        self.contacts = contacts
        self.outreach = outreach
        self.application = application
        self.resume = resume
        self.evidence = evidence
        self.stage = stage
        self.linkedTaskID = linkedTaskID
    }

    private enum CodingKeys: String, CodingKey {
        case track, priority, employer, role, location, posting, position, contacts
        case outreach, application, resume, evidence, stage, linkedTaskID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        track = try container.decodeIfPresent(JobSearchTrack.self, forKey: .track)
        priority = try container.decodePatch(Int.self, forKey: .priority)
        employer = try container.decodeIfPresent(String.self, forKey: .employer)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        location = try container.decodeIfPresent(JobLocationPatch.self, forKey: .location)
        posting = try container.decodeIfPresent(JobPostingPatch.self, forKey: .posting)
        position = try container.decodeIfPresent(JobPositionPatch.self, forKey: .position)
        contacts = try container.decodeIfPresent([JobContact].self, forKey: .contacts)
        outreach = try container.decodeIfPresent(JobOutreachPatch.self, forKey: .outreach)
        application = try container.decodeIfPresent(JobApplicationPatch.self, forKey: .application)
        resume = try container.decodeIfPresent(JobResumePatch.self, forKey: .resume)
        evidence = try container.decodeIfPresent([JobEvidence].self, forKey: .evidence)
        stage = try container.decodeIfPresent(JobStage.self, forKey: .stage)
        linkedTaskID = try container.decodePatch(TaskID.self, forKey: .linkedTaskID)
    }
}

private extension KeyedDecodingContainer {
    func decodePatch<Value: Codable & Equatable & Sendable>(
        _ type: Value.Type,
        forKey key: Key
    ) throws -> PatchValue<Value>? {
        guard contains(key) else { return nil }
        return try decode(PatchValue<Value>.self, forKey: key)
    }
}
