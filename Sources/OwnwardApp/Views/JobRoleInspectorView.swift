import SwiftUI
import OwnwardCore

struct JobRoleInspectorView: View {
    @Bindable var model: AppModel
    let role: JobRole
    @Environment(\.ownwardTheme) private var theme
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                actions

                JobInspectorSection("Application") {
                    applicationContent
                }

                JobInspectorSection("Posting") {
                    postingContent
                }

                if hasPositionDetails {
                    JobInspectorSection("Role Details") {
                        roleDetailsContent
                    }
                }

                if !role.contacts.isEmpty {
                    JobInspectorSection("Public Contacts") {
                        contactsContent
                    }
                }

                if hasOutreachGuidance {
                    JobInspectorSection("Application Guidance") {
                        guidanceContent
                    }
                }

                if !role.evidence.isEmpty {
                    JobInspectorSection("Evidence") {
                        evidenceContent
                    }
                }

                if !model.activities(for: role.id).isEmpty {
                    JobInspectorSection("History") {
                        activityContent
                    }
                }

                footer
            }
        }
        .background(theme.isSystem ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(theme.surface))
        .sheet(isPresented: $isEditing) {
            JobRoleEditor(role: role) { model.updateJobRole($0) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "briefcase")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(role.employer)
                    .font(theme.uiFont(16, weight: .semibold))
                    .lineLimit(2)
                Text(role.role)
                    .font(theme.uiFont(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button { model.selectedJobRoleID = nil } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close opportunity inspector")
        }
        .padding(14)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { model.openPosting(for: role) } label: {
                    Label("Open Posting", systemImage: "arrow.up.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(role.posting.jobURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button { model.openResume(for: role) } label: {
                    Label("Show Resume in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .help("Reveal the recorded .tex resume source in Finder")
            }
            .controlSize(.small)

            HStack {
                Picker("Stage", selection: stageBinding) {
                    ForEach(JobStage.allCases) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()
                Button("Edit") { isEditing = true }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var applicationContent: some View {
        if role.application.applied {
            JobDetailLine(
                "Applied",
                value: role.application.dateApplied?.formatted(date: .abbreviated, time: .omitted) ?? "Yes"
            )
        } else {
            HStack {
                Text("Not applied yet")
                    .font(theme.uiFont(11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Mark Applied") { model.markJobApplied(role.id) }
                    .controlSize(.small)
            }
        }

        if role.application.contacted {
            JobDetailLine("Contacted", value: "Yes")
        }
        if let followUp = role.application.followUpDate {
            JobDetailLine("Follow-up", value: followUp.formatted(date: .abbreviated, time: .omitted), emphasis: isOverdue(followUp))
        }
        if let lastMailChecked = role.application.lastMailChecked {
            JobDetailLine("Mail checked", value: lastMailChecked.formatted(date: .abbreviated, time: .omitted))
        }
        if !role.application.response.isEmpty {
            JobTextBlock(label: "Response", text: role.application.response)
        }
        if !role.application.notes.isEmpty {
            JobTextBlock(label: "Notes", text: role.application.notes)
        }
        if let linkedTask {
            Button { model.revealLinkedApplicationTask(for: role) } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checklist")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Application Task")
                            .font(theme.uiFont(11, weight: .medium))
                        Text(linkedTask.title)
                            .font(theme.metadataFont(9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open linked application task, \(linkedTask.title)")
        } else if role.linkedTaskID != nil {
            JobDetailLine("Application task", value: "Unavailable")
        }
    }

    @ViewBuilder
    private var postingContent: some View {
        JobDetailLine("Track", value: role.track.title)
        if let priority = role.priority { JobDetailLine("Priority", value: "\(priority)") }
        if !role.location.displayName.isEmpty { JobDetailLine("Location", value: role.location.displayName) }
        if !role.location.workArrangement.isEmpty { JobDetailLine("Arrangement", value: role.location.workArrangement) }
        if let posted = role.posting.postedDate {
            JobDetailLine("Posted", value: posted.formatted(date: .abbreviated, time: .omitted))
        }
        if let deadline = role.posting.deadlineDate {
            JobDetailLine(
                "Deadline",
                value: deadline.formatted(date: .abbreviated, time: .omitted),
                emphasis: JobSearchOrganizer.nextAction(for: role)?.kind == .deadline && isOverdue(deadline)
            )
        }
        if !role.posting.deadlineNotes.isEmpty { JobTextBlock(label: "Deadline notes", text: role.posting.deadlineNotes) }
        if !role.posting.status.isEmpty { JobDetailLine("Posting", value: role.posting.status) }
        if !role.posting.verificationTier.isEmpty { JobDetailLine("Evidence", value: role.posting.verificationTier) }
        if let verified = role.posting.lastVerified {
            JobDetailLine("Verified", value: verified.formatted(date: .abbreviated, time: .omitted))
        }
        if !role.posting.officialCareersURL.isEmpty {
            Button { model.openCareersPage(for: role) } label: {
                Label("Open Careers Page", systemImage: "arrow.up.right")
            }
            .buttonStyle(.plain)
            .font(theme.uiFont(11, weight: .medium))
        }
    }

    @ViewBuilder
    private var roleDetailsContent: some View {
        if !role.position.compensation.isEmpty { JobDetailLine("Compensation", value: role.position.compensation) }
        if !role.position.employmentType.isEmpty { JobDetailLine("Type", value: role.position.employmentType) }
        if !role.position.experienceRequirement.isEmpty {
            JobTextBlock(label: "Experience", text: role.position.experienceRequirement)
        }
        if !role.position.relevantSkills.isEmpty {
            JobTextBlock(label: "Requirements", text: role.position.relevantSkills)
        }
    }

    private var contactsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(role.contacts) { contact in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(contact.name.isEmpty ? "Public contact" : contact.name)
                            .font(theme.uiFont(11, weight: .semibold))
                        if contact.isPrimary {
                            Text("Primary")
                                .font(theme.metadataFont(9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !contact.titleOrDepartment.isEmpty {
                        Text(contact.titleOrDepartment).foregroundStyle(.secondary)
                    }
                    if !contact.email.isEmpty { Text(contact.email).textSelection(.enabled) }
                    if !contact.phone.isEmpty { Text(contact.phone).textSelection(.enabled) }
                    if !contact.sourceURL.isEmpty {
                        Button { model.openContactSource(contact) } label: {
                            Label("Public source", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(theme.uiFont(11))
            }
        }
    }

    @ViewBuilder
    private var guidanceContent: some View {
        if !role.outreach.bestChannel.isEmpty {
            JobTextBlock(label: "Best route", text: role.outreach.bestChannel)
        }
        if !role.outreach.suggestedAngle.isEmpty {
            JobTextBlock(label: "Approach", text: role.outreach.suggestedAngle)
        }
        if !role.outreach.confidence.isEmpty {
            JobDetailLine("Confidence", value: role.outreach.confidence)
        }
    }

    private var evidenceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(role.evidence) { evidence in
                Button { model.openEvidence(evidence) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "link")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evidence.title)
                                .font(theme.uiFont(11, weight: .medium))
                                .lineLimit(2)
                            if !evidence.note.isEmpty {
                                Text(evidence.note)
                                    .font(theme.uiFont(10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.activities(for: role.id).prefix(6))) { activity in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.secondary.opacity(0.45))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.detail.isEmpty ? activity.kind.title : activity.detail)
                            .font(theme.uiFont(10))
                        Text(activity.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(theme.metadataFont(9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Created \(role.createdAt.formatted(date: .numeric, time: .shortened))")
                Text("Updated \(role.updatedAt.formatted(date: .numeric, time: .shortened))")
            }
            .font(theme.metadataFont(9))
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
    }

    private var stageBinding: Binding<JobStage> {
        Binding(get: { role.stage }, set: { model.setJobStage(role.id, to: $0) })
    }

    private var hasPositionDetails: Bool {
        !role.position.compensation.isEmpty
            || !role.position.employmentType.isEmpty
            || !role.position.experienceRequirement.isEmpty
            || !role.position.relevantSkills.isEmpty
    }

    private var hasOutreachGuidance: Bool {
        !role.outreach.bestChannel.isEmpty
            || !role.outreach.suggestedAngle.isEmpty
            || !role.outreach.confidence.isEmpty
    }

    private var linkedTask: TaskItem? {
        role.linkedTaskID.flatMap { model.snapshot.task(id: $0) }
    }

    private func isOverdue(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }
}

private extension JobActivityKind {
    var title: String {
        switch self {
        case .created: "Opportunity created"
        case .refreshed: "Evidence refreshed"
        case .updated: "Opportunity updated"
        case .stageChanged: "Stage changed"
        case .applicationUpdated: "Application updated"
        case .mailboxUpdated: "Mailbox update"
        case .linkedTaskUpdated: "Application task updated"
        case .resumeUpdated: "Resume path updated"
        }
    }
}

private struct JobInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.ownwardTheme) private var theme

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(theme.uiFont(12, weight: .semibold))
            content
        }
        .padding(14)
        Divider()
    }
}

private struct JobDetailLine: View {
    let label: String
    let value: String
    let emphasis: Bool
    @Environment(\.ownwardTheme) private var theme

    init(_ label: String, value: String, emphasis: Bool = false) {
        self.label = label
        self.value = value
        self.emphasis = emphasis
    }

    var body: some View {
        LabeledContent(label) {
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(emphasis ? OwnwardTheme.destructive : .primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(theme.uiFont(11))
    }
}

private struct JobTextBlock: View {
    let label: String
    let text: String
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(theme.metadataFont(9))
                .foregroundStyle(.secondary)
            Text(text)
                .font(theme.uiFont(11))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
