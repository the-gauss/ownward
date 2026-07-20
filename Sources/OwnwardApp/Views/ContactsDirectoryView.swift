import AppKit
import SwiftUI
import OwnwardCore

struct ContactsDirectoryView: View {
    @Bindable var model: AppModel
    @Environment(\.ownwardTheme) private var theme
    @State private var isAddingContact = false
    @State private var contactBeingEdited: JobSearchContact?

    var body: some View {
        VStack(spacing: 0) {
            header
            contactBrowser
        }
        .background(theme.isSystem ? Color.clear : theme.surface)
        .toolbar { contactsToolbar }
        .sheet(isPresented: $isAddingContact) {
            JobSearchContactEditor(contact: nil) { model.saveJobSearchContact($0) }
        }
        .sheet(item: $contactBeingEdited) { contact in
            JobSearchContactEditor(contact: contact) { model.saveJobSearchContact($0) }
        }
        .onChange(of: model.jobContactSearchText) { _, _ in reconcileSelection() }
        .onChange(of: model.jobContactFilter) { _, _ in reconcileSelection() }
        .onChange(of: model.jobContactSort) { _, _ in reconcileSelection() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Contacts Directory")
                    .font(theme.uiFont(26, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(contactCountText)
                    .font(theme.uiFont(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var contactBrowser: some View {
        if model.visibleJobSearchContacts.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "person.2")
            } description: {
                Text(emptyDescription)
            } actions: {
                if hasActiveFilter {
                    Button("Clear Search and Filters") { resetFilters() }
                } else {
                    Button("Add Contact") { isAddingContact = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selectedJobSearchContactID) {
                ForEach(groupedContacts) { group in
                    Section(group.title) {
                        ForEach(group.contacts) { contact in
                            ContactDirectoryRow(contact: contact)
                                .tag(contact.id)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Edit Contact") { contactBeingEdited = contact }
                                    if !contact.email.isEmpty {
                                        Button("Copy Email Address") { ContactClipboard.copy(contact.email) }
                                    }
                                    if !contact.phone.isEmpty {
                                        Button("Copy Phone Number") { ContactClipboard.copy(contact.phone) }
                                    }
                                    ForEach(contact.sourceURLs, id: \.self) { sourceURL in
                                        Button("Copy Public Source") { ContactClipboard.copy(sourceURL) }
                                    }
                                    Divider()
                                    Button(contact.isArchived ? "Restore Contact" : "Archive Contact") {
                                        model.setJobSearchContactArchived(contact.id, archived: !contact.isArchived)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(theme.isSystem ? Color.clear : theme.surface)
        }
    }

    @ToolbarContentBuilder
    private var contactsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { isAddingContact = true } label: {
                Label("New Contact", systemImage: "plus")
            }
            .labelStyle(.titleAndIcon)

            TextField("Search contacts", text: $model.jobContactSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)

            contactFilterMenu

            Menu {
                ForEach(JobSearchContactGroup.allCases) { group in
                    Button {
                        model.jobContactGroup = group
                    } label: {
                        if model.jobContactGroup == group {
                            Label(group.title, systemImage: "checkmark")
                        } else {
                            Text(group.title)
                        }
                    }
                }
            } label: {
                Label("Group", systemImage: "rectangle.3.group")
            }
            .help("Group contacts by company, department, response, usefulness, or relationship level")

            Menu {
                ForEach(JobSearchContactSort.allCases) { sort in
                    Button {
                        model.jobContactSort = sort
                    } label: {
                        if model.jobContactSort == sort {
                            Label(sort.title, systemImage: "checkmark")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            Button {
                contactBeingEdited = model.selectedJobSearchContact
            } label: {
                Label("Edit Contact", systemImage: "square.and.pencil")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.selectedJobSearchContactID == nil)
            .help("Select a contact to edit its relationship record")

            Button {
                guard let contact = model.selectedJobSearchContact else { return }
                model.setJobSearchContactArchived(contact.id, archived: !contact.isArchived)
            } label: {
                Label(
                    model.selectedJobSearchContact?.isArchived == true ? "Restore Contact" : "Archive Contact",
                    systemImage: model.selectedJobSearchContact?.isArchived == true ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.selectedJobSearchContactID == nil)
            .help("Archive the selected contact without deleting its relationship record")
        }
    }

    private var contactFilterMenu: some View {
        Menu {
            Section("Directory status") {
                ForEach(JobSearchContactScope.allCases) { scope in
                    filterButton(scope.title, selected: model.jobContactFilter.scope == scope) {
                        updateFilter { $0.scope = scope }
                    }
                }
            }

            Section("Usefulness") {
                filterButton("All contacts", selected: model.jobContactFilter.usefulness == nil) {
                    updateFilter { $0.usefulness = nil }
                }
                ForEach(JobContactUsefulness.allCases) { usefulness in
                    filterButton(usefulness.title, selected: model.jobContactFilter.usefulness == usefulness) {
                        updateFilter { $0.usefulness = usefulness }
                    }
                }
            }

            Section("Response") {
                filterButton("All responses", selected: model.jobContactFilter.responseStatus == nil) {
                    updateFilter { $0.responseStatus = nil }
                }
                ForEach(JobContactResponseStatus.allCases) { status in
                    filterButton(status.title, selected: model.jobContactFilter.responseStatus == status) {
                        updateFilter { $0.responseStatus = status }
                    }
                }
            }

            Section("Relationship level") {
                filterButton("All levels", selected: model.jobContactFilter.relationshipLevel == nil) {
                    updateFilter { $0.relationshipLevel = nil }
                }
                ForEach(0...5, id: \.self) { level in
                    filterButton(
                        "Level \(level) — \(JobSearchContact.relationshipLevelTitle(level))",
                        selected: model.jobContactFilter.relationshipLevel == level
                    ) {
                        updateFilter { $0.relationshipLevel = level }
                    }
                }
            }

            Section("Follow-up") {
                ForEach(JobSearchContactFollowUpFilter.allCases) { followUp in
                    filterButton(followUp.title, selected: model.jobContactFilter.followUp == followUp) {
                        updateFilter { $0.followUp = followUp }
                    }
                }
            }

            if model.jobContactFilter.isActive {
                Divider()
                Button("Clear Filters") { model.jobContactFilter = JobSearchContactFilter() }
            }
        } label: {
            Label(
                model.jobContactFilter.isActive
                    ? "Filter \(activeFilterCount)"
                    : "Filter",
                systemImage: model.jobContactFilter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter contacts by directory status, usefulness, response, relationship level, or follow-up")
    }

    private var groupedContacts: [ContactDirectoryGroup] {
        let contacts = model.visibleJobSearchContacts
        guard model.jobContactGroup != .none else {
            return [ContactDirectoryGroup(title: "All Contacts", contacts: contacts)]
        }

        let titles = contacts.reduce(into: [String]()) { titles, contact in
            let title = model.jobContactGroup.title(for: contact)
            if !titles.contains(title) { titles.append(title) }
        }
        return titles.map { title in
            ContactDirectoryGroup(
                title: title,
                contacts: contacts.filter { model.jobContactGroup.title(for: $0) == title }
            )
        }
    }

    private var contactCountText: String {
        let visible = model.visibleJobSearchContacts.count
        let total = model.jobSearchContactCount(for: model.jobContactFilter.scope)
        let noun = total == 1 ? "contact" : "contacts"
        return hasActiveFilter ? "\(visible) of \(total) \(noun)" : "\(total) \(noun)"
    }

    private var hasActiveFilter: Bool {
        model.jobContactFilter.isActive || !model.jobContactSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeFilterCount: Int {
        [
            model.jobContactFilter.usefulness != nil,
            model.jobContactFilter.responseStatus != nil,
            model.jobContactFilter.relationshipLevel != nil,
            model.jobContactFilter.followUp != .all,
            model.jobContactFilter.scope != .active,
        ].filter { $0 }.count
    }

    private var emptyTitle: String {
        hasActiveFilter ? "No Matching Contacts" : "No Contacts Yet"
    }

    private var emptyDescription: String {
        hasActiveFilter
            ? "Change the search or filters to see more contacts."
            : "Add a contact here, or let the weekly role search add publicly sourced contacts."
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private func updateFilter(_ mutate: (inout JobSearchContactFilter) -> Void) {
        var filter = model.jobContactFilter
        mutate(&filter)
        model.jobContactFilter = filter
    }

    private func resetFilters() {
        model.jobContactSearchText = ""
        model.jobContactFilter = JobSearchContactFilter()
    }

    private func reconcileSelection() {
        guard let selected = model.selectedJobSearchContactID,
              !model.visibleJobSearchContacts.contains(where: { $0.id == selected }) else {
            return
        }
        model.selectedJobSearchContactID = nil
    }
}

private struct ContactDirectoryGroup: Identifiable {
    let title: String
    let contacts: [JobSearchContact]
    var id: String { title }
}

private struct ContactDirectoryRow: View {
    let contact: JobSearchContact
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(contact.name.isEmpty ? "Public contact" : contact.name)
                        .font(theme.uiFont(13, weight: .semibold))
                        .lineLimit(1)
                    if contact.isPrimary {
                        Text("Primary")
                            .font(theme.metadataFont(9))
                            .foregroundStyle(.secondary)
                    }
                }

                Text([contact.titleOrDepartment, contact.company]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(theme.uiFont(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if contact.hasRoute {
                    HStack(spacing: 10) {
                        if !contact.email.isEmpty {
                            ContactRouteControl(
                                title: contact.email,
                                systemImage: "envelope",
                                destination: JobSearchContactRoutes.mailtoURL(for: contact.email),
                                copyValue: contact.email,
                                copyLabel: "Copy email address"
                            )
                        }
                        if !contact.phone.isEmpty {
                            ContactRouteControl(
                                title: contact.phone,
                                systemImage: "phone",
                                destination: JobSearchContactRoutes.phoneURL(for: contact.phone),
                                copyValue: contact.phone,
                                copyLabel: "Copy phone number"
                            )
                        }
                        if let sourceURL = contact.sourceURLs.first {
                            ContactRouteControl(
                                title: JobSearchContactRoutes.publicSourceTitle(for: sourceURL),
                                systemImage: "link",
                                destination: JobSearchContactRoutes.publicSourceURL(for: sourceURL),
                                copyValue: sourceURL,
                                copyLabel: "Copy public source URL"
                            )
                        }
                        if contact.sourceURLs.count > 1 {
                            Menu {
                                ForEach(Array(contact.sourceURLs.dropFirst()), id: \.self) { sourceURL in
                                    if let destination = JobSearchContactRoutes.publicSourceURL(for: sourceURL) {
                                        Link("Open \(JobSearchContactRoutes.publicSourceTitle(for: sourceURL))", destination: destination)
                                    }
                                    Button("Copy \(JobSearchContactRoutes.publicSourceTitle(for: sourceURL))") {
                                        ContactClipboard.copy(sourceURL)
                                    }
                                }
                            } label: {
                                Label("\(contact.sourceURLs.count - 1) more", systemImage: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .help("Open or copy the remaining public sources")
                        }
                    }
                    .font(theme.uiFont(10))
                    .foregroundStyle(.secondary)
                }

                if contact.opportunities.count > 1 {
                    Text("Linked to \(contact.opportunities.count) opportunities")
                        .font(theme.metadataFont(9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(contact.usefulness.title)
                    .font(theme.metadataFont(9))
                    .foregroundStyle(usefulnessColor)
                Text(contact.responseStatus.title)
                    .font(theme.uiFont(10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Level \(contact.relationshipLevel) · \(contact.relationshipLevelTitle)")
                    .font(theme.uiFont(10))
                    .foregroundStyle(levelColor)
                if let archivedAt = contact.archivedAt {
                    Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(theme.metadataFont(9))
                        .foregroundStyle(.secondary)
                } else if let followUp = contact.nextFollowUpDate {
                    Text("Follow up \(followUp.formatted(date: .abbreviated, time: .omitted))")
                        .font(theme.metadataFont(9))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Active \(contact.lastActivityAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(theme.metadataFont(9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 155, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private var usefulnessColor: Color {
        switch contact.usefulness {
        case .useful: OwnwardTheme.success
        case .notUseful: .secondary
        case .unknown: .secondary
        }
    }

    private var levelColor: Color {
        switch contact.relationshipLevel {
        case 0: .secondary
        case 4...5: OwnwardTheme.success
        default: .primary
        }
    }

}

private struct ContactRouteControl: View {
    let title: String
    let systemImage: String
    let destination: URL?
    let copyValue: String
    let copyLabel: String

    var body: some View {
        HStack(spacing: 3) {
            if let destination {
                Link(destination: destination) {
                    Label(title, systemImage: systemImage)
                        .lineLimit(1)
                }
                .help("Open \(title)")
            } else {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
            }

            Button { ContactClipboard.copy(copyValue) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(copyLabel)
            .accessibilityLabel(copyLabel)
        }
    }
}

private enum ContactClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct JobSearchContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ownwardTheme) private var theme
    @State private var draft: JobSearchContact
    let onSave: (JobSearchContact) -> Void

    init(contact: JobSearchContact?, onSave: @escaping (JobSearchContact) -> Void) {
        _draft = State(initialValue: contact ?? JobSearchContact())
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Contact") {
                    TextField("Name", text: $draft.name)
                    TextField("Company", text: $draft.company)
                    TextField("Title or department", text: $draft.titleOrDepartment)
                    TextField("Email", text: $draft.email)
                    TextField("Phone", text: $draft.phone)
                    Toggle("Primary contact", isOn: $draft.isPrimary)
                }

                Section {
                    Picker("Usefulness", selection: $draft.usefulness) {
                        ForEach(JobContactUsefulness.allCases) { usefulness in
                            Text(usefulness.title).tag(usefulness)
                        }
                    }
                    Picker("Response", selection: $draft.responseStatus) {
                        ForEach(JobContactResponseStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Contact level", selection: $draft.relationshipLevel) {
                        ForEach(0...5, id: \.self) { level in
                            Text("Level \(level) — \(JobSearchContact.relationshipLevelTitle(level))").tag(level)
                        }
                    }
                    Toggle("Record first contact", isOn: optionalDateEnabled(\.firstContactedAt))
                    if draft.firstContactedAt != nil {
                        DatePicker("First contacted", selection: optionalDate(\.firstContactedAt), displayedComponents: .date)
                    }
                    Toggle("Record last contact", isOn: optionalDateEnabled(\.lastContactedAt))
                    if draft.lastContactedAt != nil {
                        DatePicker("Last contacted", selection: optionalDate(\.lastContactedAt), displayedComponents: .date)
                    }
                    Toggle("Record response", isOn: optionalDateEnabled(\.lastRespondedAt))
                    if draft.lastRespondedAt != nil {
                        DatePicker("Last response", selection: optionalDate(\.lastRespondedAt), displayedComponents: .date)
                    }
                    Toggle("Schedule follow-up", isOn: optionalDateEnabled(\.nextFollowUpDate))
                    if draft.nextFollowUpDate != nil {
                        DatePicker("Next follow-up", selection: optionalDate(\.nextFollowUpDate), displayedComponents: .date)
                    }
                } header: {
                    Text("Relationship")
                } footer: {
                    Text("Level 0 means ghosted. Level 5 is a high-quality, multi-day conversation of at least four to five turns where they are unlikely to forget you.")
                }

                Section("Public research") {
                    TextField("Source confidence", text: $draft.confidence)
                    TextEditor(text: sourceURLsText)
                        .font(theme.uiFont(12))
                        .frame(minHeight: 64)
                        .overlay(alignment: .topLeading) {
                            if draft.sourceURLs.isEmpty {
                                Text("Public source URLs (one per line)")
                                    .font(theme.uiFont(12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(theme.uiFont(12))
                        .frame(minHeight: 90)
                }

                if !draft.opportunities.isEmpty {
                    Section("Linked opportunities") {
                        ForEach(draft.opportunities) { opportunity in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(opportunity.company) — \(opportunity.roleTitle)")
                                Text([opportunity.department, opportunity.location.displayName, opportunity.track.title]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .foregroundStyle(.secondary)
                            }
                            .font(theme.uiFont(11))
                        }
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.hasRoute)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 650)
    }

    private var sourceURLsText: Binding<String> {
        Binding(
            get: { draft.sourceURLs.joined(separator: "\n") },
            set: { draft.sourceURLs = $0.components(separatedBy: .newlines) }
        )
    }

    private func optionalDate(_ keyPath: WritableKeyPath<JobSearchContact, Date?>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath] ?? Date() },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func optionalDateEnabled(_ keyPath: WritableKeyPath<JobSearchContact, Date?>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] != nil },
            set: { enabled in draft[keyPath: keyPath] = enabled ? (draft[keyPath: keyPath] ?? Date()) : nil }
        )
    }
}
