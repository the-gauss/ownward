import SwiftUI
import OwnwardCore

struct MainContentView: View {
    @Bindable var model: AppModel
    @Environment(\.ownwardTheme) private var theme
    @State private var isAdjustingTaskColumn = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(theme.uiFont(26, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 14)

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
            .frame(width: geometry.size.width / model.zoomScale, height: geometry.size.height / model.zoomScale)
            .scaleEffect(model.zoomScale, anchor: .topLeading)
        }
        .background(theme.isSystem ? Color.clear : theme.surface)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.createTask() } label: { Label("New Task", systemImage: "plus") }
                    .labelStyle(.titleAndIcon)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                Picker("View", selection: $model.viewMode) {
                    ForEach(MainViewMode.allCases) { mode in
                        Image(systemName: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
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
                Button {
                    if model.selectedTaskID != nil { model.selectedTaskID = nil }
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }
                .labelStyle(.titleAndIcon)
                .help("Select a task to open the inspector")
            }
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
