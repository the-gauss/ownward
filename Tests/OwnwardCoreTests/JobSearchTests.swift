import Foundation
import Testing
@testable import OwnwardCore

@Suite("Job Search domain")
struct JobSearchTests {
    @Test("verified refreshes are idempotent and preserve human workflow state")
    func upsertPreservesHumanState() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshedAt = createdAt.addingTimeInterval(86_400)
        let appliedAt = createdAt.addingTimeInterval(3_600)
        let linkedTaskID = TaskID()
        var workspace = JobSearchWorkspace()
        var role = sampleRole(createdAt: createdAt)

        #expect(try JobSearchEngine.upsert(role, in: &workspace, at: createdAt) == .inserted)
        let roleID = try #require(workspace.roles.first?.id)
        try JobSearchEngine.update(
            roleID,
            patch: JobRolePatch(
                application: JobApplicationPatch(
                    applied: true,
                    dateApplied: .value(appliedAt),
                    notes: "Submitted by me; preserve this."
                ),
                stage: .applied,
                linkedTaskID: .value(linkedTaskID)
            ),
            activityKind: .applicationUpdated,
            activityDetail: "Marked applied",
            in: &workspace,
            at: appliedAt
        )

        role.posting.status = "Open — reverified"
        role.posting.lastVerified = refreshedAt
        role.posting.jobURL = "https://example.ca/jobs/data-analyst/?utm_source=weekly"
        role.resume.sourcePath = "/tmp/tailored.pdf"
        role.stage = .readyToApply

        #expect(try JobSearchEngine.upsert(role, in: &workspace, at: refreshedAt) == .updated)
        #expect(workspace.roles.count == 1)
        #expect(workspace.roles[0].id == roleID)
        #expect(workspace.roles[0].posting.status == "Open — reverified")
        #expect(workspace.roles[0].application.applied)
        #expect(workspace.roles[0].application.dateApplied == appliedAt)
        #expect(workspace.roles[0].application.notes == "Submitted by me; preserve this.")
        #expect(workspace.roles[0].stage == .applied)
        #expect(workspace.roles[0].linkedTaskID == linkedTaskID)
        #expect(workspace.roles[0].resume.sourcePath == "/tmp/tailored.pdf")
        #expect(workspace.activities.map(\.kind) == [.created, .applicationUpdated, .refreshed])
    }

    @Test("canonical URLs and normalized fallback fields prevent duplicates")
    func stableOpportunityIdentity() throws {
        var workspace = JobSearchWorkspace()
        let original = sampleRole(createdAt: .now)
        var queryVariant = original
        queryVariant.employer = "  EXAMPLE   COUNTY "
        queryVariant.role = "data analyst"
        queryVariant.location.province = "on"
        queryVariant.posting.jobURL = "HTTPS://example.ca/jobs/data-analyst?utm_campaign=test#apply"

        _ = try JobSearchEngine.upsert(original, in: &workspace)
        _ = try JobSearchEngine.upsert(queryVariant, in: &workspace)

        #expect(workspace.roles.count == 1)
    }

    @Test("smart scopes separate active, closed, and archived records")
    func smartScopes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var ready = sampleRole(createdAt: now)
        ready.stage = .readyToApply
        var followUp = sampleRole(createdAt: now)
        followUp.id = JobRoleID()
        followUp.employer = "Follow Up Co"
        followUp.posting.jobURL = "https://follow.example/job"
        followUp.stage = .applied
        followUp.application.applied = true
        followUp.application.followUpDate = now.addingTimeInterval(-3_600)
        var futureFollowUp = followUp
        futureFollowUp.id = JobRoleID()
        futureFollowUp.employer = "Future Follow Up Co"
        futureFollowUp.posting.jobURL = "https://future-follow-up.example/job"
        futureFollowUp.application.followUpDate = now.addingTimeInterval(86_400)
        var interview = sampleRole(createdAt: now)
        interview.id = JobRoleID()
        interview.employer = "Interview Co"
        interview.posting.jobURL = "https://interview.example/job"
        interview.stage = .interviewing
        var closed = sampleRole(createdAt: now)
        closed.id = JobRoleID()
        closed.employer = "Closed Co"
        closed.posting.jobURL = "https://closed.example/job"
        closed.stage = .closed
        var archived = sampleRole(createdAt: now)
        archived.id = JobRoleID()
        archived.employer = "Archived Co"
        archived.posting.jobURL = "https://archived.example/job"
        archived.stage = .archived
        archived.application.applied = true

        let roles = [ready, followUp, futureFollowUp, interview, closed, archived]

        #expect(JobSearchOrganizer.roles(roles, scope: .needsAction, now: now).map(\.employer) == ["Follow Up Co", "Example County"])
        #expect(JobSearchOrganizer.roles(roles, scope: .followUps, now: now).map(\.employer) == ["Follow Up Co", "Future Follow Up Co"])
        #expect(JobSearchOrganizer.roles(roles, scope: .interviews, now: now).map(\.employer) == ["Interview Co"])
        #expect(JobSearchOrganizer.roles(roles, scope: .closed, now: now).map(\.employer) == ["Closed Co"])
        #expect(JobSearchOrganizer.roles(roles, scope: .archive, now: now).map(\.employer) == ["Archived Co"])
        #expect(!JobSearchOrganizer.roles(roles, scope: .all, now: now).contains(where: { $0.stage == .archived }))
        #expect(!JobSearchOrganizer.roles(roles, scope: .applications, now: now).contains(where: { $0.stage == .archived }))
    }

    @Test("four-week archive policy protects live interviews and offers")
    func archivePolicy() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 10))!
        let twentyNineDaysAgo = calendar.date(byAdding: .day, value: -29, to: now)!
        let twentySevenDaysAgo = calendar.date(byAdding: .day, value: -27, to: now)!

        var staleApplied = sampleRole(createdAt: twentyNineDaysAgo)
        staleApplied.stage = .applied
        staleApplied.application.applied = true
        staleApplied.application.dateApplied = twentyNineDaysAgo

        var recentApplied = staleApplied
        recentApplied.id = JobRoleID()
        recentApplied.application.dateApplied = twentySevenDaysAgo

        var interviewing = staleApplied
        interviewing.id = JobRoleID()
        interviewing.stage = .interviewing

        var offer = staleApplied
        offer.id = JobRoleID()
        offer.stage = .offer

        #expect(JobArchivePolicy.isEligible(staleApplied, asOf: now, calendar: calendar))
        #expect(!JobArchivePolicy.isEligible(recentApplied, asOf: now, calendar: calendar))
        #expect(!JobArchivePolicy.isEligible(interviewing, asOf: now, calendar: calendar))
        #expect(!JobArchivePolicy.isEligible(offer, asOf: now, calendar: calendar))
    }

    @Test("search spans the fields a person remembers instead of database columns")
    func humanSearch() {
        var role = sampleRole(createdAt: .now)
        role.contacts = [JobContact(name: "Avery Chen", titleOrDepartment: "Recruitment")]
        role.application.notes = "Referral from the municipal analytics meetup"

        #expect(JobSearchOrganizer.roles([role], search: "avery").count == 1)
        #expect(JobSearchOrganizer.roles([role], search: "municipal").count == 1)
        #expect(JobSearchOrganizer.roles([role], search: "thunder bay").count == 1)
        #expect(JobSearchOrganizer.roles([role], search: "unrelated").isEmpty)
    }

    @Test("nullable patches can deliberately clear a follow-up without replacing application history")
    func nullablePatchClearsDate() throws {
        var workspace = JobSearchWorkspace(roles: [sampleRole(createdAt: .now)])
        let id = workspace.roles[0].id
        workspace.roles[0].application.applied = true
        workspace.roles[0].application.response = "Acknowledged"
        workspace.roles[0].application.followUpDate = .now

        try JobSearchEngine.update(
            id,
            patch: JobRolePatch(application: JobApplicationPatch(followUpDate: .null)),
            in: &workspace
        )

        #expect(workspace.roles[0].application.followUpDate == nil)
        #expect(workspace.roles[0].application.applied)
        #expect(workspace.roles[0].application.response == "Acknowledged")
    }

    @Test("replayed no-op patches do not duplicate activity history")
    func noOpPatchIsIdempotent() throws {
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        var role = sampleRole(createdAt: originalDate)
        role.stage = .applied
        role.application.applied = true
        var workspace = JobSearchWorkspace(roles: [role])

        try JobSearchEngine.update(
            role.id,
            patch: JobRolePatch(stage: .applied),
            activityKind: .stageChanged,
            activityDetail: "Stage changed to Applied.",
            in: &workspace,
            at: originalDate.addingTimeInterval(60)
        )

        #expect(workspace.roles[0].updatedAt == originalDate)
        #expect(workspace.activities.isEmpty)

        try JobSearchEngine.update(
            role.id,
            patch: JobRolePatch(stage: .archived),
            activityKind: .stageChanged,
            activityDetail: "Automatically archived 28 days after application.",
            in: &workspace,
            at: originalDate.addingTimeInterval(120)
        )

        #expect(workspace.roles[0].stage == .archived)
        #expect(workspace.activities.map(\.detail) == ["Automatically archived 28 days after application."])
    }

    @Test("next action stops treating a posting deadline as actionable after application")
    func applicationNextAction() throws {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let followUp = deadline.addingTimeInterval(86_400)
        var role = sampleRole(createdAt: deadline.addingTimeInterval(-604_800))
        role.posting.deadlineDate = deadline

        let readyAction = try #require(JobSearchOrganizer.nextAction(for: role))
        #expect(readyAction.kind == .deadline)
        #expect(readyAction.date == deadline)

        role.stage = .applied
        role.application.applied = true
        #expect(JobSearchOrganizer.nextAction(for: role) == nil)

        role.application.followUpDate = followUp
        let appliedAction = try #require(JobSearchOrganizer.nextAction(for: role))
        #expect(appliedAction.kind == .followUp)
        #expect(appliedAction.date == followUp)
    }

    @Test("weekly contact refreshes build one durable directory record without replacing relationship history")
    func contactDirectoryAccumulatesAcrossWeeklyRefreshes() throws {
        let firstSeen = Date(timeIntervalSince1970: 1_800_000_000)
        let refresh = firstSeen.addingTimeInterval(7 * 86_400)
        var role = sampleRole(createdAt: firstSeen)
        role.contacts = [JobContact(
            name: "Avery Chen",
            titleOrDepartment: "Talent Acquisition",
            email: "avery@example.ca",
            sourceURL: "https://example.ca/team/avery",
            confidence: "Public company profile",
            isPrimary: true
        )]
        var workspace = JobSearchWorkspace()

        _ = try JobSearchEngine.upsert(role, in: &workspace, at: firstSeen)
        #expect(workspace.contacts.count == 1)
        #expect(workspace.contacts[0].company == "Example County")
        #expect(workspace.contacts[0].relationshipLevel == 1)
        #expect(workspace.contacts[0].opportunities.map(\.roleID) == [workspace.roles[0].id])

        var relationship = workspace.contacts[0]
        relationship.usefulness = .useful
        relationship.responseStatus = .responded
        relationship.relationshipLevel = 5
        relationship.lastContactedAt = firstSeen.addingTimeInterval(86_400)
        relationship.lastRespondedAt = firstSeen.addingTimeInterval(2 * 86_400)
        relationship.notes = "Thoughtful multi-day conversation about the analytics team."
        try JobSearchEngine.saveContact(relationship, in: &workspace, at: relationship.lastRespondedAt!)

        role.contacts = [JobContact(
            name: "Avery Chen",
            titleOrDepartment: "Senior Talent Partner",
            email: "avery@example.ca",
            sourceURL: "https://example.ca/careers/contact",
            confidence: "Official careers page"
        )]
        _ = try JobSearchEngine.upsert(role, in: &workspace, at: refresh)

        let contact = try #require(workspace.contacts.first)
        #expect(workspace.contacts.count == 1)
        #expect(contact.titleOrDepartment == "Senior Talent Partner")
        #expect(contact.sourceURLs == [
            "https://example.ca/team/avery",
            "https://example.ca/careers/contact",
        ])
        #expect(contact.usefulness == .useful)
        #expect(contact.responseStatus == .responded)
        #expect(contact.relationshipLevel == 5)
        #expect(contact.notes == "Thoughtful multi-day conversation about the analytics team.")
        #expect(contact.firstSeenAt == firstSeen)
        #expect(contact.lastSeenAt == refresh)
    }

    @Test("contact directory searches, filters, sorts, and labels useful groups")
    func contactDirectoryOrganization() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let engaged = JobSearchContact(
            name: "Avery Chen",
            company: "Example County",
            titleOrDepartment: "Talent Acquisition",
            email: "avery@example.ca",
            usefulness: .useful,
            responseStatus: .responded,
            relationshipLevel: 5,
            lastRespondedAt: now
        )
        let waiting = JobSearchContact(
            name: "Morgan Patel",
            company: "Northwind Labs",
            titleOrDepartment: "Engineering",
            phone: "555-0100",
            usefulness: .notUseful,
            responseStatus: .noResponse,
            relationshipLevel: 0,
            lastContactedAt: now.addingTimeInterval(-86_400)
        )

        let responded = JobSearchContactOrganizer.contacts(
            [waiting, engaged],
            filter: JobSearchContactFilter(responseStatus: .responded),
            sort: .relationshipLevel
        )
        #expect(responded.map(\.name) == ["Avery Chen"])
        #expect(JobSearchContactOrganizer.contacts([waiting, engaged], search: "engineering").map(\.id) == [waiting.id])
        #expect(JobSearchContactOrganizer.contacts([waiting, engaged], sort: .relationshipLevel).map(\.id) == [engaged.id, waiting.id])
        #expect(JobSearchContactGroup.department.title(for: engaged) == "Talent Acquisition")
        #expect(JobSearchContactGroup.relationshipLevel.title(for: waiting) == "Level 0 — Ghosted")
    }

    @Test("contact archive state is reversible, filterable, and survives a weekly refresh")
    func contactDirectoryArchiveState() throws {
        let firstSeen = Date(timeIntervalSince1970: 1_800_000_000)
        let archivedAt = firstSeen.addingTimeInterval(86_400)
        let refresh = archivedAt.addingTimeInterval(7 * 86_400)
        var role = sampleRole(createdAt: firstSeen)
        role.contacts = [JobContact(name: "Avery Chen", email: "avery@example.ca")]
        var workspace = JobSearchWorkspace()

        _ = try JobSearchEngine.upsert(role, in: &workspace, at: firstSeen)
        let contactID = try #require(workspace.contacts.first?.id)
        try JobSearchEngine.setContactArchived(contactID, archived: true, in: &workspace, at: archivedAt)

        #expect(workspace.contacts.first?.archivedAt == archivedAt)
        #expect(JobSearchContactOrganizer.contacts(workspace.contacts).isEmpty)
        #expect(JobSearchContactOrganizer.contacts(
            workspace.contacts,
            filter: JobSearchContactFilter(scope: .archived)
        ).map(\.id) == [contactID])
        #expect(JobSearchContactOrganizer.contacts(
            workspace.contacts,
            filter: JobSearchContactFilter(scope: .all)
        ).map(\.id) == [contactID])

        role.contacts = [JobContact(
            name: "Avery Chen",
            titleOrDepartment: "Talent Acquisition",
            email: "avery@example.ca",
            sourceURL: "https://example.ca/careers"
        )]
        _ = try JobSearchEngine.upsert(role, in: &workspace, at: refresh)

        let refreshed = try #require(workspace.contacts.first)
        #expect(refreshed.archivedAt == archivedAt)
        #expect(refreshed.titleOrDepartment == "Talent Acquisition")

        try JobSearchEngine.setContactArchived(contactID, archived: false, in: &workspace, at: refresh)
        #expect(workspace.contacts.first?.archivedAt == nil)
        #expect(JobSearchContactOrganizer.contacts(workspace.contacts).map(\.id) == [contactID])
    }

    private func sampleRole(createdAt: Date) -> JobRole {
        JobRole(
            track: .backup,
            priority: 1,
            employer: "Example County",
            role: "Data Analyst",
            location: JobLocation(city: "Thunder Bay", province: "ON", workArrangement: "Hybrid"),
            posting: JobPosting(
                status: "Open",
                verificationTier: "Official exact posting",
                jobURL: "https://example.ca/jobs/data-analyst",
                officialCareersURL: "https://example.ca/careers",
                postedDate: createdAt,
                deadlineDate: createdAt.addingTimeInterval(604_800),
                lastVerified: createdAt
            ),
            position: JobPositionDetails(compensation: "$70,000", employmentType: "Full-time"),
            stage: .readyToApply,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
