import Foundation

public enum JobRoleUpsertOutcome: Equatable, Sendable {
    case inserted
    case updated
}

public enum JobSearchEngine {
    @discardableResult
    public static func upsert(
        _ incoming: JobRole,
        in workspace: inout JobSearchWorkspace,
        at date: Date = Date()
    ) throws -> JobRoleUpsertOutcome {
        var verified = incoming
        normalize(&verified)
        try validate(verified)

        if let index = workspace.roles.firstIndex(where: { $0.identity.matches(verified.identity) }) {
            let existing = workspace.roles[index]
            verified.id = existing.id
            verified.createdAt = existing.createdAt
            verified.updatedAt = date
            verified.application = existing.application
            verified.linkedTaskID = existing.linkedTaskID
            verified.location = merging(verified.location, over: existing.location)
            verified.posting = merging(verified.posting, over: existing.posting)
            verified.position = merging(verified.position, over: existing.position)
            verified.contacts = verified.contacts.isEmpty ? existing.contacts : verified.contacts
            verified.outreach = isEmpty(verified.outreach) ? existing.outreach : verified.outreach
            verified.resume = isEmpty(verified.resume) ? existing.resume : verified.resume
            verified.evidence = verified.evidence.isEmpty ? existing.evidence : verified.evidence
            verified.stage = preservedStage(existing: existing, incoming: verified.stage)
            enforceApplicationInvariant(&verified)
            workspace.roles[index] = verified
            workspace.activities.append(JobActivity(
                roleID: verified.id,
                date: date,
                kind: .refreshed,
                detail: "Verified role evidence refreshed."
            ))
            return .updated
        }

        verified.createdAt = min(verified.createdAt, date)
        verified.updatedAt = date
        enforceApplicationInvariant(&verified)
        workspace.roles.append(verified)
        workspace.activities.append(JobActivity(
            roleID: verified.id,
            date: date,
            kind: .created,
            detail: "Verified role added to the \(verified.track.title) track."
        ))
        return .inserted
    }

    public static func update(
        _ roleID: JobRoleID,
        patch: JobRolePatch,
        activityKind: JobActivityKind = .updated,
        activityDetail: String = "Role updated.",
        in workspace: inout JobSearchWorkspace,
        at date: Date = Date()
    ) throws {
        guard let index = workspace.roles.firstIndex(where: { $0.id == roleID }) else {
            throw DomainError.jobRoleNotFound
        }
        let existingRole = workspace.roles[index]
        var role = existingRole
        apply(patch, to: &role)
        normalize(&role)
        try validate(role)
        enforceApplicationInvariant(&role)
        guard role != existingRole else { return }
        role.updatedAt = date
        workspace.roles[index] = role
        workspace.activities.append(JobActivity(
            roleID: roleID,
            date: date,
            kind: activityKind,
            detail: activityDetail
        ))
    }

    public static func replace(
        _ edited: JobRole,
        activityKind: JobActivityKind = .updated,
        activityDetail: String = "Role updated.",
        in workspace: inout JobSearchWorkspace,
        at date: Date = Date()
    ) throws {
        guard let index = workspace.roles.firstIndex(where: { $0.id == edited.id }) else {
            throw DomainError.jobRoleNotFound
        }
        var normalized = edited
        normalized.createdAt = workspace.roles[index].createdAt
        normalized.updatedAt = date
        normalize(&normalized)
        try validate(normalized)
        enforceApplicationInvariant(&normalized)
        workspace.roles[index] = normalized
        workspace.activities.append(JobActivity(
            roleID: edited.id,
            date: date,
            kind: activityKind,
            detail: activityDetail
        ))
    }

    private static func validate(_ role: JobRole) throws {
        guard !role.employer.isEmpty, !role.role.isEmpty else { throw DomainError.invalidJobRole }
    }

    private static func normalize(_ role: inout JobRole) {
        role.employer = role.employer.trimmingCharacters(in: .whitespacesAndNewlines)
        role.role = role.role.trimmingCharacters(in: .whitespacesAndNewlines)
        role.location.city = role.location.city.trimmingCharacters(in: .whitespacesAndNewlines)
        role.location.province = role.location.province.trimmingCharacters(in: .whitespacesAndNewlines)
        role.location.workArrangement = role.location.workArrangement.trimmingCharacters(in: .whitespacesAndNewlines)
        role.posting.jobURL = role.posting.jobURL.trimmingCharacters(in: .whitespacesAndNewlines)
        role.posting.officialCareersURL = role.posting.officialCareersURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preservedStage(existing: JobRole, incoming: JobStage) -> JobStage {
        if incoming == .closed { return .closed }
        if existing.stage.isApplicationStage || existing.stage == .archived { return existing.stage }
        if existing.application.applied { return .applied }
        return incoming
    }

    private static func enforceApplicationInvariant(_ role: inout JobRole) {
        if role.stage.isApplicationStage { role.application.applied = true }
        if role.application.applied && !role.stage.isApplicationStage && !role.stage.isTerminal {
            role.stage = .applied
        }
    }

    private static func merging(_ incoming: JobLocation, over existing: JobLocation) -> JobLocation {
        JobLocation(
            city: incoming.city.isEmpty ? existing.city : incoming.city,
            province: incoming.province.isEmpty ? existing.province : incoming.province,
            workArrangement: incoming.workArrangement.isEmpty ? existing.workArrangement : incoming.workArrangement
        )
    }

    private static func merging(_ incoming: JobPosting, over existing: JobPosting) -> JobPosting {
        JobPosting(
            status: incoming.status.isEmpty ? existing.status : incoming.status,
            verificationTier: incoming.verificationTier.isEmpty ? existing.verificationTier : incoming.verificationTier,
            jobURL: incoming.jobURL.isEmpty ? existing.jobURL : incoming.jobURL,
            officialCareersURL: incoming.officialCareersURL.isEmpty ? existing.officialCareersURL : incoming.officialCareersURL,
            postedDate: incoming.postedDate ?? existing.postedDate,
            deadlineDate: incoming.deadlineDate ?? existing.deadlineDate,
            deadlineNotes: incoming.deadlineNotes.isEmpty ? existing.deadlineNotes : incoming.deadlineNotes,
            lastVerified: incoming.lastVerified ?? existing.lastVerified
        )
    }

    private static func merging(_ incoming: JobPositionDetails, over existing: JobPositionDetails) -> JobPositionDetails {
        JobPositionDetails(
            compensation: incoming.compensation.isEmpty ? existing.compensation : incoming.compensation,
            employmentType: incoming.employmentType.isEmpty ? existing.employmentType : incoming.employmentType,
            experienceRequirement: incoming.experienceRequirement.isEmpty ? existing.experienceRequirement : incoming.experienceRequirement,
            relevantSkills: incoming.relevantSkills.isEmpty ? existing.relevantSkills : incoming.relevantSkills
        )
    }

    private static func isEmpty(_ value: JobOutreach) -> Bool {
        value.bestChannel.isEmpty && value.suggestedAngle.isEmpty && value.confidence.isEmpty
    }

    private static func isEmpty(_ value: JobResume) -> Bool {
        value.sourcePath.isEmpty && value.factCheckStatus.isEmpty && value.lastReviewed == nil
    }

    private static func apply(_ patch: JobRolePatch, to role: inout JobRole) {
        if let track = patch.track { role.track = track }
        apply(patch.priority, to: &role.priority)
        if let employer = patch.employer { role.employer = employer }
        if let title = patch.role { role.role = title }
        if let location = patch.location {
            if let city = location.city { role.location.city = city }
            if let province = location.province { role.location.province = province }
            if let arrangement = location.workArrangement { role.location.workArrangement = arrangement }
        }
        if let posting = patch.posting {
            if let status = posting.status { role.posting.status = status }
            if let tier = posting.verificationTier { role.posting.verificationTier = tier }
            if let url = posting.jobURL { role.posting.jobURL = url }
            if let url = posting.officialCareersURL { role.posting.officialCareersURL = url }
            apply(posting.postedDate, to: &role.posting.postedDate)
            apply(posting.deadlineDate, to: &role.posting.deadlineDate)
            if let notes = posting.deadlineNotes { role.posting.deadlineNotes = notes }
            apply(posting.lastVerified, to: &role.posting.lastVerified)
        }
        if let position = patch.position {
            if let value = position.compensation { role.position.compensation = value }
            if let value = position.employmentType { role.position.employmentType = value }
            if let value = position.experienceRequirement { role.position.experienceRequirement = value }
            if let value = position.relevantSkills { role.position.relevantSkills = value }
        }
        if let contacts = patch.contacts { role.contacts = contacts }
        if let outreach = patch.outreach {
            if let value = outreach.bestChannel { role.outreach.bestChannel = value }
            if let value = outreach.suggestedAngle { role.outreach.suggestedAngle = value }
            if let value = outreach.confidence { role.outreach.confidence = value }
        }
        if let application = patch.application {
            if let applied = application.applied {
                role.application.applied = applied
                if !applied, patch.stage == nil, role.stage == .applied { role.stage = .readyToApply }
            }
            apply(application.dateApplied, to: &role.application.dateApplied)
            if let contacted = application.contacted { role.application.contacted = contacted }
            apply(application.followUpDate, to: &role.application.followUpDate)
            if let response = application.response { role.application.response = response }
            if let notes = application.notes { role.application.notes = notes }
            apply(application.lastMailChecked, to: &role.application.lastMailChecked)
        }
        if let resume = patch.resume {
            if let path = resume.sourcePath { role.resume.sourcePath = path }
            if let status = resume.factCheckStatus { role.resume.factCheckStatus = status }
            apply(resume.lastReviewed, to: &role.resume.lastReviewed)
        }
        if let evidence = patch.evidence { role.evidence = evidence }
        if let stage = patch.stage { role.stage = stage }
        apply(patch.linkedTaskID, to: &role.linkedTaskID)
    }

    private static func apply<Value>(_ patch: PatchValue<Value>?, to value: inout Value?) {
        guard let patch else { return }
        switch patch {
        case .value(let newValue): value = newValue
        case .null: value = nil
        }
    }
}

public enum JobSearchOrganizer {
    public static func nextAction(for role: JobRole) -> JobNextAction? {
        if let followUpDate = role.application.followUpDate, !role.stage.isTerminal {
            return JobNextAction(kind: .followUp, date: followUpDate)
        }
        if !role.application.applied,
           role.stage == .researching || role.stage == .readyToApply,
           let deadlineDate = role.posting.deadlineDate {
            return JobNextAction(kind: .deadline, date: deadlineDate)
        }
        return nil
    }

    public static func roles(
        _ roles: [JobRole],
        scope: JobSearchScope = .all,
        track: JobSearchTrack? = nil,
        search: String = "",
        sort: JobSearchSort = .nextAction,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [JobRole] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return roles
            .filter { role in
                (track == nil || role.track == track)
                    && matches(role, scope: scope, now: now, calendar: calendar)
                    && (query.isEmpty || searchText(for: role).localizedCaseInsensitiveContains(query))
            }
            .sorted { left, right in compare(left, right, by: sort, now: now) }
    }

    public static func count(
        _ roles: [JobRole],
        scope: JobSearchScope,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        roles.count { matches($0, scope: scope, now: now, calendar: calendar) }
    }

    private static func matches(_ role: JobRole, scope: JobSearchScope, now: Date, calendar: Calendar) -> Bool {
        switch scope {
        case .all:
            return role.stage != .archived
        case .needsAction:
            if role.stage == .researching || role.stage == .readyToApply { return true }
            guard !role.stage.isTerminal, let followUp = role.application.followUpDate else { return false }
            return calendar.startOfDay(for: followUp) <= calendar.startOfDay(for: now)
        case .applications:
            return role.stage != .archived && (role.application.applied || role.stage.isApplicationStage)
        case .interviews:
            return role.stage == .interviewing || role.stage == .offer
        case .followUps:
            return !role.stage.isTerminal && role.application.followUpDate != nil
        case .closed:
            return role.stage == .closed || role.stage == .rejected
        case .archive:
            return role.stage == .archived
        }
    }

    private static func searchText(for role: JobRole) -> String {
        let contacts = role.contacts.flatMap {
            [$0.name, $0.titleOrDepartment, $0.email, $0.phone]
        }
        return ([
            role.employer,
            role.role,
            role.location.city,
            role.location.province,
            role.location.workArrangement,
            role.posting.status,
            role.posting.verificationTier,
            role.position.compensation,
            role.position.employmentType,
            role.position.experienceRequirement,
            role.position.relevantSkills,
            role.application.response,
            role.application.notes,
            role.outreach.bestChannel,
            role.outreach.suggestedAngle,
        ] + contacts).joined(separator: "\n")
    }

    private static func compare(_ left: JobRole, _ right: JobRole, by sort: JobSearchSort, now: Date) -> Bool {
        switch sort {
        case .recentlyUpdated:
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        case .employer:
            let comparison = left.employer.localizedCaseInsensitiveCompare(right.employer)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        case .priority:
            if (left.priority ?? .max) != (right.priority ?? .max) {
                return (left.priority ?? .max) < (right.priority ?? .max)
            }
        case .nextAction:
            if left.stage.isTerminal != right.stage.isTerminal { return !left.stage.isTerminal }
            let leftDate = nextAction(for: left)?.date
            let rightDate = nextAction(for: right)?.date
            switch (leftDate, rightDate) {
            case (let lhs?, let rhs?) where lhs != rhs: return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if (left.priority ?? .max) != (right.priority ?? .max) {
                return (left.priority ?? .max) < (right.priority ?? .max)
            }
        }
        let employerComparison = left.employer.localizedCaseInsensitiveCompare(right.employer)
        if employerComparison != .orderedSame { return employerComparison == .orderedAscending }
        return left.role.localizedCaseInsensitiveCompare(right.role) == .orderedAscending
    }
}

public enum JobArchivePolicy {
    public static let ageInDays = 28

    /// Applied records move out of the active dashboard after four weeks, but
    /// an interview or offer remains live regardless of age.
    public static func isEligible(
        _ role: JobRole,
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard role.application.applied,
              let dateApplied = role.application.dateApplied,
              [.applied, .rejected, .closed].contains(role.stage),
              let cutoff = calendar.date(
                byAdding: .day,
                value: -ageInDays,
                to: calendar.startOfDay(for: date)
              ) else {
            return false
        }
        return calendar.startOfDay(for: dateApplied) <= cutoff
    }
}
