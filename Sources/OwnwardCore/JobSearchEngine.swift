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
            synchronizeDirectoryContacts(for: verified, in: &workspace, at: date)
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
        synchronizeDirectoryContacts(for: verified, in: &workspace, at: date)
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
        if patch.contacts != nil {
            synchronizeDirectoryContacts(for: role, in: &workspace, at: date)
        }
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
        synchronizeDirectoryContacts(for: normalized, in: &workspace, at: date)
        workspace.activities.append(JobActivity(
            roleID: edited.id,
            date: date,
            kind: activityKind,
            detail: activityDetail
        ))
    }

    /// Backfills contact records from already-persisted roles during a schema
    /// upgrade. It only adds or refreshes research facts; relationship history
    /// stored in the directory remains user-owned.
    public static func reconcileContactDirectory(in workspace: inout JobSearchWorkspace) {
        for role in workspace.roles {
            synchronizeDirectoryContacts(
                for: role,
                in: &workspace,
                at: role.updatedAt,
                firstSeenAt: role.createdAt
            )
        }
    }

    /// Removes legacy "no contact found" placeholders that earlier research
    /// records encoded as contacts. Human-edited records are deliberately kept.
    public static func removePlaceholderDirectoryContacts(in workspace: inout JobSearchWorkspace) {
        workspace.contacts.removeAll { contact in
            isDirectoryPlaceholder(name: contact.name, titleOrDepartment: contact.titleOrDepartment)
                && contact.usefulness == .unknown
                && contact.responseStatus == .notContacted
                && contact.relationshipLevel == 1
                && contact.firstContactedAt == nil
                && contact.lastContactedAt == nil
                && contact.lastRespondedAt == nil
                && contact.nextFollowUpDate == nil
                && contact.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public static func saveContact(
        _ edited: JobSearchContact,
        in workspace: inout JobSearchWorkspace,
        at date: Date = Date()
    ) throws {
        var normalized = edited
        normalize(&normalized)
        try validate(normalized)

        if let index = workspace.contacts.firstIndex(where: { $0.id == normalized.id }) {
            let existing = workspace.contacts[index]
            normalized.createdAt = existing.createdAt
            normalized.firstSeenAt = min(existing.firstSeenAt, normalized.firstSeenAt)
            normalized.lastSeenAt = max(existing.lastSeenAt, normalized.lastSeenAt)
            normalized.opportunities = existing.opportunities
            normalized.updatedAt = date
            workspace.contacts[index] = normalized
            return
        }

        normalized.createdAt = min(normalized.createdAt, date)
        normalized.updatedAt = date
        workspace.contacts.append(normalized)
    }

    /// Archiving is a reversible directory-only action. It never changes the
    /// source role contacts, so future research refreshes retain the user's
    /// archive decision rather than recreating an active duplicate.
    public static func setContactArchived(
        _ contactID: JobSearchContactID,
        archived: Bool,
        in workspace: inout JobSearchWorkspace,
        at date: Date = Date()
    ) throws {
        guard let index = workspace.contacts.firstIndex(where: { $0.id == contactID }) else {
            throw DomainError.jobSearchContactNotFound
        }
        guard workspace.contacts[index].isArchived != archived else { return }
        workspace.contacts[index].archivedAt = archived ? date : nil
        workspace.contacts[index].updatedAt = date
    }

    private static func validate(_ role: JobRole) throws {
        guard !role.employer.isEmpty, !role.role.isEmpty else { throw DomainError.invalidJobRole }
    }

    private static func validate(_ contact: JobSearchContact) throws {
        guard !contact.name.isEmpty || contact.hasRoute else { throw DomainError.invalidJobContact }
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

    private static func normalize(_ contact: inout JobSearchContact) {
        contact.name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.company = contact.company.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.titleOrDepartment = contact.titleOrDepartment.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.email = contact.email.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.phone = contact.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.confidence = contact.confidence.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.notes = contact.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.sourceURLs = uniqueNonempty(contact.sourceURLs)
        contact.relationshipLevel = min(5, max(0, contact.relationshipLevel))
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

    private static func synchronizeDirectoryContacts(
        for role: JobRole,
        in workspace: inout JobSearchWorkspace,
        at date: Date,
        firstSeenAt: Date? = nil
    ) {
        for imported in role.contacts where hasDirectoryValue(imported) {
            let incoming = directoryContact(
                from: imported,
                role: role,
                firstSeenAt: firstSeenAt ?? date,
                lastSeenAt: date
            )
            if let index = workspace.contacts.firstIndex(where: { matches($0, incoming) }) {
                workspace.contacts[index] = merging(incoming, over: workspace.contacts[index], at: date)
            } else {
                workspace.contacts.append(incoming)
            }
        }
    }

    private static func directoryContact(
        from contact: JobContact,
        role: JobRole,
        firstSeenAt: Date,
        lastSeenAt: Date
    ) -> JobSearchContact {
        let opportunity = JobContactOpportunity(
            roleID: role.id,
            company: role.employer,
            roleTitle: role.role,
            department: contact.titleOrDepartment,
            location: role.location,
            track: role.track,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt
        )
        return JobSearchContact(
            name: contact.name,
            company: role.employer,
            titleOrDepartment: contact.titleOrDepartment,
            email: contact.email,
            phone: contact.phone,
            sourceURLs: contact.sourceURL.isEmpty ? [] : [contact.sourceURL],
            confidence: contact.confidence,
            isPrimary: contact.isPrimary,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt,
            opportunities: [opportunity],
            createdAt: firstSeenAt,
            updatedAt: lastSeenAt
        )
    }

    private static func merging(
        _ incoming: JobSearchContact,
        over existing: JobSearchContact,
        at date: Date
    ) -> JobSearchContact {
        var merged = existing
        merged.name = incoming.name.isEmpty ? existing.name : incoming.name
        merged.company = existing.company.isEmpty ? incoming.company : existing.company
        merged.titleOrDepartment = incoming.titleOrDepartment.isEmpty
            ? existing.titleOrDepartment
            : incoming.titleOrDepartment
        merged.email = incoming.email.isEmpty ? existing.email : incoming.email
        merged.phone = incoming.phone.isEmpty ? existing.phone : incoming.phone
        merged.sourceURLs = uniqueNonempty(existing.sourceURLs + incoming.sourceURLs)
        merged.confidence = incoming.confidence.isEmpty ? existing.confidence : incoming.confidence
        merged.isPrimary = existing.isPrimary || incoming.isPrimary
        merged.firstSeenAt = min(existing.firstSeenAt, incoming.firstSeenAt)
        merged.lastSeenAt = max(existing.lastSeenAt, incoming.lastSeenAt)
        merged.opportunities = merging(incoming.opportunities, over: existing.opportunities, at: date)
        merged.updatedAt = date
        return merged
    }

    private static func merging(
        _ incoming: [JobContactOpportunity],
        over existing: [JobContactOpportunity],
        at date: Date
    ) -> [JobContactOpportunity] {
        var merged = existing
        for opportunity in incoming {
            if let index = merged.firstIndex(where: { $0.roleID == opportunity.roleID }) {
                var refreshed = opportunity
                refreshed.firstSeenAt = min(merged[index].firstSeenAt, opportunity.firstSeenAt)
                refreshed.lastSeenAt = max(merged[index].lastSeenAt, date)
                merged[index] = refreshed
            } else {
                merged.append(opportunity)
            }
        }
        return merged
    }

    private static func matches(_ left: JobSearchContact, _ right: JobSearchContact) -> Bool {
        let leftEmail = normalizedEmail(left.email)
        let rightEmail = normalizedEmail(right.email)
        if !leftEmail.isEmpty, leftEmail == rightEmail { return true }

        let leftPhone = normalizedPhone(left.phone)
        let rightPhone = normalizedPhone(right.phone)
        if !leftPhone.isEmpty, leftPhone == rightPhone { return true }

        let sameCompany = normalizedText(left.company) == normalizedText(right.company)
        let leftName = normalizedText(left.name)
        let rightName = normalizedText(right.name)
        if sameCompany, !leftName.isEmpty, leftName == rightName { return true }

        return sameCompany && !Set(left.sourceURLs.map(normalizedURL)).isDisjoint(
            with: Set(right.sourceURLs.map(normalizedURL))
        )
    }

    private static func hasDirectoryValue(_ contact: JobContact) -> Bool {
        guard !isDirectoryPlaceholder(name: contact.name, titleOrDepartment: contact.titleOrDepartment) else {
            return false
        }
        return [contact.name, contact.titleOrDepartment, contact.email, contact.phone, contact.sourceURL]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isDirectoryPlaceholder(name: String, titleOrDepartment: String) -> Bool {
        let normalizedName = normalizedText(name)
        let normalizedTitle = normalizedText(titleOrDepartment)
        return [
            "none",
            "n/a",
            "na",
            "not available",
            "no contact found",
            "no verified public contact found",
        ].contains(normalizedName) || [
            "no contact found",
            "no verified public contact found",
        ].contains(normalizedTitle)
    }

    private static func uniqueNonempty(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !result.contains(where: { normalizedURL($0) == normalizedURL(value) }) else {
                return
            }
            result.append(value)
        }
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedPhone(_ value: String) -> String {
        value.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.map(String.init).joined()
    }

    private static func normalizedText(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

public enum JobSearchContactOrganizer {
    public static func contacts(
        _ contacts: [JobSearchContact],
        filter: JobSearchContactFilter = JobSearchContactFilter(),
        search: String = "",
        sort: JobSearchContactSort = .relationshipLevel,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [JobSearchContact] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return contacts
            .filter { contact in
                matches(contact, filter: filter, now: now, calendar: calendar)
                    && (query.isEmpty || searchText(for: contact).localizedCaseInsensitiveContains(query))
            }
            .sorted { compare($0, $1, by: sort) }
    }

    private static func matches(
        _ contact: JobSearchContact,
        filter: JobSearchContactFilter,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard (filter.usefulness == nil || contact.usefulness == filter.usefulness),
              (filter.responseStatus == nil || contact.responseStatus == filter.responseStatus),
              (filter.relationshipLevel == nil || contact.relationshipLevel == filter.relationshipLevel) else {
            return false
        }

        switch filter.scope {
        case .active:
            guard !contact.isArchived else { return false }
        case .archived:
            guard contact.isArchived else { return false }
        case .all:
            break
        }

        switch filter.followUp {
        case .all:
            return true
        case .due:
            guard let date = contact.nextFollowUpDate else { return false }
            return calendar.startOfDay(for: date) <= calendar.startOfDay(for: now)
        case .scheduled:
            return contact.nextFollowUpDate != nil
        case .none:
            return contact.nextFollowUpDate == nil
        }
    }

    private static func searchText(for contact: JobSearchContact) -> String {
        let opportunityText = contact.opportunities.flatMap {
            [$0.company, $0.roleTitle, $0.department, $0.location.displayName, $0.location.workArrangement, $0.track.title]
        }
        return ([
            contact.name,
            contact.company,
            contact.titleOrDepartment,
            contact.email,
            contact.phone,
            contact.confidence,
            contact.usefulness.title,
            contact.responseStatus.title,
            contact.relationshipLevelTitle,
            contact.notes,
        ] + contact.sourceURLs + opportunityText).joined(separator: "\n")
    }

    private static func compare(
        _ left: JobSearchContact,
        _ right: JobSearchContact,
        by sort: JobSearchContactSort
    ) -> Bool {
        switch sort {
        case .relationshipLevel:
            if left.relationshipLevel != right.relationshipLevel {
                return left.relationshipLevel > right.relationshipLevel
            }
            if left.lastActivityAt != right.lastActivityAt { return left.lastActivityAt > right.lastActivityAt }
        case .recentlyActive:
            if left.lastActivityAt != right.lastActivityAt { return left.lastActivityAt > right.lastActivityAt }
        case .name:
            let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        case .company:
            let comparison = left.company.localizedCaseInsensitiveCompare(right.company)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        case .followUp:
            switch (left.nextFollowUpDate, right.nextFollowUpDate) {
            case (let lhs?, let rhs?) where lhs != rhs: return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
        }

        let nameComparison = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        return left.company.localizedCaseInsensitiveCompare(right.company) == .orderedAscending
    }
}

public extension JobSearchContactGroup {
    func title(for contact: JobSearchContact) -> String {
        switch self {
        case .none: "All Contacts"
        case .company: contact.company.isEmpty ? "No company" : contact.company
        case .department: contact.titleOrDepartment.isEmpty ? "No department" : contact.titleOrDepartment
        case .responseStatus: contact.responseStatus.title
        case .usefulness: contact.usefulness.title
        case .relationshipLevel:
            "Level \(contact.relationshipLevel) — \(contact.relationshipLevelTitle)"
        }
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
