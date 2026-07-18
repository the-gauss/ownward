import SwiftUI
import OwnwardCore

struct JobRoleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ownwardTheme) private var theme
    @State private var draft: JobRole
    @State private var priorityText: String
    let isNew: Bool
    let onSave: (JobRole) -> Void

    init(role: JobRole?, onSave: @escaping (JobRole) -> Void) {
        let initial = role ?? JobRole(track: .backup, employer: "", role: "")
        _draft = State(initialValue: initial)
        _priorityText = State(initialValue: initial.priority.map(String.init) ?? "")
        isNew = role == nil
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Opportunity") {
                    TextField("Employer", text: $draft.employer)
                    TextField("Role", text: $draft.role)
                    Picker("Track", selection: $draft.track) {
                        ForEach(JobSearchTrack.allCases) { track in
                            Text(track.title).tag(track)
                        }
                    }
                    Picker("Stage", selection: $draft.stage) {
                        ForEach(JobStage.allCases) { stage in
                            Text(stage.title).tag(stage)
                        }
                    }
                    TextField("Priority", text: $priorityText, prompt: Text("Optional number"))
                }

                Section("Location") {
                    TextField("City", text: $draft.location.city)
                    TextField("Province", text: $draft.location.province)
                    TextField("Work arrangement", text: $draft.location.workArrangement, prompt: Text("Remote, hybrid, or on-site"))
                }

                Section("Posting") {
                    TextField("Direct posting URL", text: $draft.posting.jobURL)
                    TextField("Careers page URL", text: $draft.posting.officialCareersURL)
                    TextField("Posting status", text: $draft.posting.status)
                    TextField("Verification tier", text: $draft.posting.verificationTier)

                    Toggle("Has deadline", isOn: optionalDateEnabled(\.posting.deadlineDate))
                    if draft.posting.deadlineDate != nil {
                        DatePicker("Deadline", selection: optionalDate(\.posting.deadlineDate), displayedComponents: .date)
                        TextField("Deadline notes", text: $draft.posting.deadlineNotes)
                    }

                    Toggle("Has posted date", isOn: optionalDateEnabled(\.posting.postedDate))
                    if draft.posting.postedDate != nil {
                        DatePicker("Posted", selection: optionalDate(\.posting.postedDate), displayedComponents: .date)
                    }
                }

                Section("Application") {
                    Toggle("Applied", isOn: $draft.application.applied)
                    if draft.application.applied {
                        Toggle("Record application date", isOn: optionalDateEnabled(\.application.dateApplied))
                        if draft.application.dateApplied != nil {
                            DatePicker("Applied", selection: optionalDate(\.application.dateApplied), displayedComponents: .date)
                        }
                    }
                    Toggle("Contacted", isOn: $draft.application.contacted)
                    Toggle("Schedule follow-up", isOn: optionalDateEnabled(\.application.followUpDate))
                    if draft.application.followUpDate != nil {
                        DatePicker("Follow-up", selection: optionalDate(\.application.followUpDate), displayedComponents: .date)
                    }
                    TextField("Response", text: $draft.application.response)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").foregroundStyle(.secondary)
                        TextEditor(text: $draft.application.notes)
                            .font(theme.uiFont(12))
                            .frame(minHeight: 90)
                            .padding(6)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                Section("Role Details") {
                    TextField("Compensation", text: $draft.position.compensation)
                    TextField("Employment type", text: $draft.position.employmentType)
                    TextField("Experience requirement", text: $draft.position.experienceRequirement)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Requirements and skills").foregroundStyle(.secondary)
                        TextEditor(text: $draft.position.relevantSkills)
                            .font(theme.uiFont(12))
                            .frame(minHeight: 80)
                            .padding(6)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Add Opportunity" : "Edit Opportunity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 620, idealHeight: 720)
        .background(theme.isSystem ? Color.clear : theme.surface)
        .onChange(of: draft.stage) { _, stage in
            if stage.isApplicationStage { draft.application.applied = true }
        }
        .onChange(of: draft.application.applied) { _, applied in
            if applied, draft.application.dateApplied == nil { draft.application.dateApplied = Date() }
            if applied, !draft.stage.isApplicationStage, !draft.stage.isTerminal { draft.stage = .applied }
            if !applied, draft.stage == .applied { draft.stage = .readyToApply }
        }
    }

    private var isValid: Bool {
        !draft.employer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func optionalDate(_ keyPath: WritableKeyPath<JobRole, Date?>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath] ?? Date() },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func optionalDateEnabled(_ keyPath: WritableKeyPath<JobRole, Date?>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] != nil },
            set: { enabled in
                if enabled, draft[keyPath: keyPath] == nil { draft[keyPath: keyPath] = Date() }
                if !enabled { draft[keyPath: keyPath] = nil }
            }
        )
    }

    private func save() {
        let normalizedPriority = priorityText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.priority = normalizedPriority.isEmpty ? nil : Int(normalizedPriority)
        onSave(draft)
        dismiss()
    }
}
