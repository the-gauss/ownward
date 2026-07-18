import SwiftUI
import OwnwardCore

struct MainContentView: View {
    @Bindable var model: AppModel
    @Environment(\.ownwardTheme) private var theme
    @State private var isAdjustingTaskColumn = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(theme.uiFont(26, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text(taskCountText)
                        .font(theme.uiFont(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if model.visibleTasks.isEmpty {
                projectEmptyState
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                Group {
                    switch model.viewMode {
                    case .kanban: KanbanView(model: model)
                    case .table: TaskTableView(model: model)
                    case .timeline: TimelineView(model: model)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(theme.isSystem ? Color.clear : theme.surface)
        .onChange(of: model.projectTaskFilter) { _, _ in reconcileSelection() }
        .onChange(of: model.searchText) { _, _ in reconcileSelection() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.createTask() } label: { Label("New Task", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Picker("View", selection: $model.viewMode) {
                    ForEach(MainViewMode.allCases) { mode in
                        Image(systemName: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                Menu {
                    ForEach(groupingOptions, id: \.self) { grouping in
                        Button {
                            activeGrouping = grouping
                        } label: {
                            if activeGrouping == grouping { Label(grouping.title, systemImage: "checkmark") }
                            else { Text(grouping.title) }
                        }
                    }
                } label: {
                    Label("Group", systemImage: "rectangle.3.group")
                }
                Menu {
                    if model.viewMode == .timeline {
                        Label("Start Date", systemImage: "checkmark")
                    } else {
                        ForEach(sortOptions, id: \.self) { sort in
                            Button {
                                activeSort = sort
                            } label: {
                                if activeSort == sort { Label(sort.title, systemImage: "checkmark") }
                                else { Text(sort.title) }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                projectFilterMenu
                if model.viewMode == .table {
                    Button { isAdjustingTaskColumn.toggle() } label: {
                        Label("Task Column Width", systemImage: "arrow.left.and.right")
                    }
                    .popover(isPresented: $isAdjustingTaskColumn, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Task Column")
                                    .font(theme.uiFont(13, weight: .semibold))
                                Spacer()
                                Text("\(Int(model.tableTaskColumnWidth)) pt")
                                    .font(theme.metadataFont(10))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: $model.tableTaskColumnWidth,
                                in: TableTaskColumnWidth.minimum...TableTaskColumnWidth.maximum,
                                step: 10
                            )
                            HStack {
                                Text("Narrow").foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") { model.resetTableTaskColumnWidth() }
                                Spacer()
                                Text("Wide").foregroundStyle(.secondary)
                            }
                            .font(theme.uiFont(10))
                        }
                        .padding(14)
                        .frame(width: 280)
                        .background(theme.isSystem ? Color.clear : theme.surface)
                    }
                    .help("Adjust Task column width")
                }
            }
        }
    }

    @ViewBuilder
    private var projectEmptyState: some View {
        ContentUnavailableView {
            Label(hasProjectQuery ? "No Matching Tasks" : "No Tasks Here", systemImage: "checklist")
        } description: {
            Text(hasProjectQuery
                 ? "Change the search or filters to see more work."
                 : "This project view has no tasks yet.")
        } actions: {
            if hasProjectQuery {
                Button("Clear Search and Filters") {
                    model.searchText = ""
                    model.resetTaskFilters()
                }
            } else if case .board = model.sidebarSelection {
                Button("New Task") { model.createTask() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectFilterMenu: some View {
        Menu {
            Section("Status") {
                filterButton("All Statuses", selected: model.projectTaskFilter.status == nil) {
                    model.setProjectStatusFilter(nil)
                }
                ForEach(model.availableProjectStatuses, id: \.self) { status in
                    filterButton(status.title, selected: model.projectTaskFilter.status == status) {
                        model.setProjectStatusFilter(status)
                    }
                }
            }
            Section("Team") {
                filterButton("All Teams", selected: model.projectTaskFilter.team == .all) {
                    model.setProjectTeamFilter(.all)
                }
                ForEach(model.availableProjectTeams, id: \.self) { team in
                    filterButton(team, selected: model.projectTaskFilter.team == .named(team)) {
                        model.setProjectTeamFilter(.named(team))
                    }
                }
                if model.hasUnassignedProjectTasks {
                    filterButton("No Team", selected: model.projectTaskFilter.team == .unassigned) {
                        model.setProjectTeamFilter(.unassigned)
                    }
                }
            }
            Section("Dates") {
                ForEach(TaskDateFilter.allCases) { dateFilter in
                    filterButton(dateFilter.title, selected: model.projectTaskFilter.date == dateFilter) {
                        model.setProjectDateFilter(dateFilter)
                    }
                }
            }
            if model.projectTaskFilter.isActive {
                Divider()
                Button("Clear Filters") { model.resetTaskFilters() }
            }
        } label: {
            Label(
                model.projectTaskFilter.isActive
                    ? "Filter \(model.projectTaskFilter.activeCriterionCount)"
                    : "Filter",
                systemImage: model.projectTaskFilter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help(model.projectTaskFilter.isActive
              ? "\(model.projectTaskFilter.activeCriterionCount) active task filters"
              : "Filter tasks by status, team, or dates")
    }

    private func filterButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private var taskCountText: String {
        let visible = model.visibleTasks.count
        let total = model.projectScopeTaskCount
        let noun = total == 1 ? "task" : "tasks"
        return hasProjectQuery ? "\(visible) of \(total) \(noun)" : "\(total) \(noun)"
    }

    private var hasProjectQuery: Bool {
        model.projectTaskFilter.isActive
            || !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reconcileSelection() {
        guard let selected = model.selectedTaskID else { return }
        if !model.visibleTasks.contains(where: { $0.id == selected }) {
            model.selectedTaskID = nil
        }
    }

    private var groupingOptions: [TaskGrouping] {
        switch model.viewMode {
        case .kanban: [.none, .team]
        case .table, .timeline: [.none, .status, .team]
        }
    }

    private var activeGrouping: TaskGrouping {
        get {
            switch model.viewMode {
            case .kanban: model.kanbanGrouping
            case .table: model.tableGrouping
            case .timeline: model.timelineGrouping
            }
        }
        nonmutating set {
            switch model.viewMode {
            case .kanban: model.kanbanGrouping = newValue
            case .table: model.tableGrouping = newValue
            case .timeline: model.timelineGrouping = newValue
            }
        }
    }

    private var sortOptions: [TaskSort] {
        [.manual, .deadline, .checklistProgress]
    }

    private var activeSort: TaskSort {
        get { model.viewMode == .kanban ? model.kanbanSort : model.tableSort }
        nonmutating set {
            if model.viewMode == .kanban { model.kanbanSort = newValue }
            else { model.tableSort = newValue }
        }
    }

    private var title: String {
        switch model.sidebarSelection {
        case .board: model.selectedBoard?.name ?? "Ownward"
        case .saved(let view): view.title
        }
    }
}
