import SwiftUI
import OwnwardCore

struct JobSearchView: View {
    @Bindable var model: AppModel
    @Environment(\.ownwardTheme) private var theme
    @State private var isAddingRole = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                roleBrowser(layout: JobSearchLayoutPolicy.layout(for: geometry.size.width))
            }
        }
        .background(theme.isSystem ? Color.clear : theme.surface)
        .toolbar { jobToolbar }
        .sheet(isPresented: $isAddingRole) {
            JobRoleEditor(role: nil) { model.createJobRole($0) }
        }
        .onChange(of: model.jobSearchText) { _, _ in reconcileSelection() }
        .onChange(of: model.jobTrackFilter) { _, _ in reconcileSelection() }
        .onChange(of: model.jobSearchSort) { _, _ in reconcileSelection() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.jobSearchScope.title)
                    .font(theme.uiFont(26, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(roleCountText)
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
    private func roleBrowser(layout: JobSearchLayout) -> some View {
        if model.visibleJobRoles.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "briefcase")
            } description: {
                Text(emptyDescription)
            } actions: {
                if hasActiveFilter {
                    Button("Show All Opportunities") {
                        model.jobSearchScope = .all
                        model.jobTrackFilter = .all
                        model.jobSearchText = ""
                    }
                } else {
                    Button("Add Opportunity") { isAddingRole = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch layout {
            case .compact:
                compactList
            case .regular:
                regularTable
            case .wide:
                wideTable
            }
        }
    }

    private var compactList: some View {
        List(selection: $model.selectedJobRoleID) {
            ForEach(model.visibleJobRoles) { role in
                JobRoleCompactRow(role: role)
                    .tag(role.id)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(theme.isSystem ? Color.clear : theme.surface)
    }

    private var regularTable: some View {
        Table(model.visibleJobRoles, selection: $model.selectedJobRoleID) {
            TableColumn("Opportunity") { role in
                JobOpportunityCell(role: role)
            }
            .width(min: 220, ideal: 300)

            TableColumn("Location") { role in
                JobLocationLabel(role: role)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Stage") { role in
                JobStageLabel(stage: role.stage)
            }
            .width(min: 115, ideal: 135)

            TableColumn("Next Date") { role in
                JobNextDateLabel(role: role)
            }
            .width(min: 105, ideal: 120)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(theme.isSystem ? Color.clear : theme.surface)
    }

    private var wideTable: some View {
        Table(model.visibleJobRoles, selection: $model.selectedJobRoleID) {
            TableColumn("Opportunity") { role in
                JobOpportunityCell(role: role)
            }
            .width(min: 260, ideal: 360)

            TableColumn("Location") { role in
                JobLocationLabel(role: role)
            }
            .width(min: 130, ideal: 170)

            TableColumn("Stage") { role in
                JobStageLabel(stage: role.stage)
            }
            .width(min: 120, ideal: 140)

            TableColumn("Track") { role in
                Text(role.track.title)
                    .font(theme.uiFont(11))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Next Date") { role in
                JobNextDateLabel(role: role)
            }
            .width(min: 115, ideal: 135)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(theme.isSystem ? Color.clear : theme.surface)
    }

    @ToolbarContentBuilder
    private var jobToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { isAddingRole = true } label: {
                Label("New Opportunity", systemImage: "plus")
            }
            .labelStyle(.titleAndIcon)

            TextField("Search opportunities", text: $model.jobSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            Menu {
                ForEach(JobTrackFilter.allCases) { filter in
                    Button {
                        model.jobTrackFilter = filter
                    } label: {
                        if model.jobTrackFilter == filter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            } label: {
                Label(model.jobTrackFilter.title, systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Filter by search track")

            Menu {
                ForEach(JobSearchSort.allCases) { sort in
                    Button {
                        model.jobSearchSort = sort
                    } label: {
                        if model.jobSearchSort == sort {
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
                if model.selectedJobRoleID != nil { model.selectedJobRoleID = nil }
            } label: {
                Label("Inspector", systemImage: "info.circle")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.selectedJobRoleID == nil)
            .help("Select an opportunity to open the inspector")
        }
    }

    private var roleCountText: String {
        let count = model.visibleJobRoles.count
        let noun = count == 1 ? "opportunity" : "opportunities"
        return "\(count) \(noun) · \(model.jobTrackFilter.title)"
    }

    private var hasActiveFilter: Bool {
        model.jobSearchScope != .all || model.jobTrackFilter != .all || !model.jobSearchText.isEmpty
    }

    private var emptyTitle: String {
        hasActiveFilter ? "No Matching Opportunities" : "No Opportunities Yet"
    }

    private var emptyDescription: String {
        hasActiveFilter
            ? "Change the current view, track, or search text."
            : "Add a role here, or let the weekly search add verified roles through Ownward."
    }

    private func reconcileSelection() {
        guard let selected = model.selectedJobRoleID else { return }
        if !model.visibleJobRoles.contains(where: { $0.id == selected }) {
            model.selectedJobRoleID = nil
        }
    }
}

struct JobStageLabel: View {
    let stage: JobStage
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        Label(stage.title, systemImage: "circle.fill")
            .labelStyle(.titleAndIcon)
            .font(theme.uiFont(11, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var color: Color {
        switch stage {
        case .researching: .secondary
        case .readyToApply: .orange
        case .applied: .blue
        case .interviewing: .purple
        case .offer: OwnwardTheme.success
        case .rejected, .closed, .archived: .secondary
        }
    }
}

private struct JobOpportunityCell: View {
    let role: JobRole
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(role.employer)
                .font(theme.uiFont(12, weight: .semibold))
                .lineLimit(1)
            Text(role.role)
                .font(theme.uiFont(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.employer), \(role.role)")
    }
}

private struct JobRoleCompactRow: View {
    let role: JobRole
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                JobOpportunityCell(role: role)
                JobLocationLabel(role: role)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                JobStageLabel(stage: role.stage)
                JobNextDateLabel(role: role)
            }
            .frame(minWidth: 112, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct JobLocationLabel: View {
    let role: JobRole
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(role.location.displayName.isEmpty ? "—" : role.location.displayName)
                .lineLimit(1)
            if !role.location.workArrangement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(role.location.workArrangement)
                    .font(theme.uiFont(9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .font(theme.uiFont(10.5))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct JobNextDateLabel: View {
    let role: JobRole
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        if let action = JobSearchOrganizer.nextAction(for: role) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.kind == .followUp ? "Follow up" : "Deadline")
                Text(action.date, format: .dateTime.month(.abbreviated).day())
            }
            .foregroundStyle(isPast(action.date) ? OwnwardTheme.destructive : .secondary)
            .font(theme.uiFont(10))
        } else {
            Text("—")
                .font(theme.uiFont(11))
                .foregroundStyle(.tertiary)
        }
    }

    private func isPast(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }
}
