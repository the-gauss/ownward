import SwiftUI
import OwnwardCore

struct KanbanView: View {
    @Bindable var model: AppModel
    @Environment(\.ownwardTheme) private var theme
    @State private var collapsedTeams: Set<String> = []

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(220, (geometry.size.width - 2) / 3)
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    ForEach(TaskStatus.boardColumns, id: \.self) { status in
                        KanbanStatusHeader(
                            model: model,
                            status: status,
                            count: model.visibleTasks.count { $0.status == status }
                        )
                        .frame(width: columnWidth)
                    }
                }
                Divider()

                if model.kanbanGrouping == .team {
                    groupedBoard(columnWidth: columnWidth)
                } else {
                    ungroupedBoard(columnWidth: columnWidth)
                }
            }
            .frame(width: columnWidth * 3 + 2, alignment: .leading)
            .background(theme.isSystem ? Color(nsColor: .controlBackgroundColor).opacity(0.35) : theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)) }
        }
    }

    private func groupedBoard(columnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(TaskOrganizer.teamSwimlanes(model.visibleTasks, sort: model.kanbanSort)) { lane in
                        Button {
                            toggleTeam(lane.id)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: collapsedTeams.contains(lane.id) ? "chevron.right" : "chevron.down")
                                    .font(theme.uiFont(9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 10)
                                Text(lane.team)
                                    .font(theme.uiFont(11, weight: .semibold))
                                Text("\(lane.count)")
                                    .font(theme.metadataFont(9))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(theme.ink.opacity(0.075))
                        .accessibilityLabel("\(lane.team), \(lane.count) tasks")
                        .accessibilityValue(collapsedTeams.contains(lane.id) ? "Collapsed" : "Expanded")

                        if !collapsedTeams.contains(lane.id) {
                            HStack(alignment: .top, spacing: 1) {
                                ForEach(TaskStatus.boardColumns, id: \.self) { status in
                                    TeamStatusCell(
                                        model: model,
                                        team: lane.team == "No Team" ? nil : lane.team,
                                        status: status,
                                        tasks: lane.tasks(in: status)
                                    )
                                    .frame(width: columnWidth)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
            Divider()
            HStack(spacing: 1) {
                ForEach(TaskStatus.boardColumns, id: \.self) { status in
                    Button { model.createTask(in: status) } label: {
                        Image(systemName: "plus").frame(maxWidth: .infinity).frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth)
                }
            }
        }
    }

    private func ungroupedBoard(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 1) {
            ForEach(TaskStatus.boardColumns, id: \.self) { status in
                KanbanStatusLane(
                    model: model,
                    status: status,
                    tasks: TaskOrganizer.sorted(model.visibleTasks.filter { $0.status == status }, by: model.kanbanSort)
                )
                .frame(width: columnWidth)
            }
        }
    }

    private func toggleTeam(_ id: String) {
        if collapsedTeams.contains(id) { collapsedTeams.remove(id) }
        else { collapsedTeams.insert(id) }
    }
}

private struct KanbanStatusHeader: View {
    @Bindable var model: AppModel
    let status: TaskStatus
    let count: Int
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        HStack {
            Circle()
                .fill(theme.statusTint(status))
                .frame(width: 6, height: 6)
            Text(status.title).font(theme.uiFont(13, weight: .semibold))
            Text("\(count)").font(theme.metadataFont(10)).foregroundStyle(.secondary)
            Spacer()
            Button { model.createTask(in: status) } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(theme.statusTint(status).opacity(0.095))
    }
}

private struct KanbanStatusLane: View {
    @Bindable var model: AppModel
    let status: TaskStatus
    let tasks: [TaskItem]
    @State private var isDropTarget = false
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tasks) { task in
                        TaskRow(model: model, task: task, showsTeam: true)
                            .dropDestination(for: String.self) { identifiers, _ in
                                guard model.kanbanSort == .manual,
                                      let value = identifiers.first,
                                      let uuid = UUID(uuidString: value) else { return false }
                                model.reorder(TaskID(rawValue: uuid), before: task.id)
                                return true
                            }
                        Divider().padding(.leading, 14)
                    }
                }
            }
            Spacer(minLength: 0)
            Divider()
            Button { model.createTask(in: status) } label: {
                Image(systemName: "plus").frame(maxWidth: .infinity).frame(height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .background(isDropTarget ? theme.statusTint(status).opacity(0.06) : Color.clear)
        .overlay(alignment: .trailing) { Divider() }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let value = identifiers.first, let uuid = UUID(uuidString: value) else { return false }
            model.move(TaskID(rawValue: uuid), to: status)
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}

private struct TeamStatusCell: View {
    @Bindable var model: AppModel
    let team: String?
    let status: TaskStatus
    let tasks: [TaskItem]
    @State private var isDropTarget = false
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(tasks) { task in
                TaskRow(model: model, task: task, showsTeam: false)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard model.kanbanSort == .manual,
                              let value = identifiers.first,
                              let uuid = UUID(uuidString: value) else { return false }
                        model.reorder(TaskID(rawValue: uuid), before: task.id, team: team)
                        return true
                    }
                Divider().padding(.leading, 14)
            }
            if tasks.isEmpty {
                Text("Drop here")
                    .font(theme.uiFont(9))
                    .foregroundStyle(isDropTarget ? theme.statusTint(status) : Color.secondary.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .top)
        .background(isDropTarget ? theme.statusTint(status).opacity(0.09) : Color.clear)
        .overlay(alignment: .trailing) { Divider() }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { identifiers, _ in
            guard let value = identifiers.first, let uuid = UUID(uuidString: value) else { return false }
            model.move(TaskID(rawValue: uuid), to: status, team: team)
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}

struct TaskRow: View {
    @Bindable var model: AppModel
    let task: TaskItem
    var showsTeam = true
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button { model.toggleTask(task) } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(task.status == .done ? OwnwardTheme.success : .secondary)
            }
            .buttonStyle(.plain)

            Button { model.selectedTaskID = task.id } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(theme.uiFont(12, weight: .medium)).lineLimit(2)
                    if showsTeam, let team = task.team {
                        Text(team).font(theme.uiFont(10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !task.miniTasks.isEmpty {
                Text("\(task.completedMiniTaskCount)/\(task.miniTasks.count)")
                    .font(theme.metadataFont(9))
                    .foregroundStyle(.secondary)
            }
            if let deadline = task.deadlineEnd ?? task.deadlineStart {
                Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                    .font(theme.uiFont(10, weight: .medium))
                    .foregroundStyle(deadline < Date() && task.status != .done ? OwnwardTheme.destructive : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(model.selectedTaskID == task.id ? theme.accent.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .draggable(task.id.description)
        .contextMenu {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button("Move to \(status.title)") { model.move(task.id, to: status) }
            }
        }
    }
}
