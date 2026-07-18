import SwiftUI
import OwnwardCore

struct TaskTableView: View {
    @Bindable var model: AppModel
    @Environment(\.ownwardTheme) private var theme
    @State private var collapsedGroups: Set<String> = []

    private let statusWidth: CGFloat = 110
    private let teamWidth: CGFloat = 150
    private let checklistWidth: CGFloat = 85
    private let deadlineWidth: CGFloat = 115

    private var groups: [TaskGroup] {
        TaskOrganizer.grouped(model.visibleTasks, by: model.tableGrouping).map {
            TaskGroup(title: $0.title, tasks: TaskOrganizer.sorted($0.tasks, by: model.tableSort))
        }
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                tableHeader
                Divider()
                ForEach(groups) { group in
                    if model.tableGrouping != .none {
                        groupHeader(group)
                    }
                    if model.tableGrouping == .none || !collapsedGroups.contains(group.id) {
                        ForEach(group.tasks) { task in
                            tableRow(task)
                            Divider().padding(.leading, CGFloat(model.tableTaskColumnWidth) + 24)
                        }
                    }
                }
            }
            .frame(width: contentWidth, alignment: .leading)
        }
        .background(theme.isSystem ? Color(nsColor: .controlBackgroundColor).opacity(0.45) : theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)) }
    }

    private func groupHeader(_ group: TaskGroup) -> some View {
        Button {
            toggle(group.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down")
                    .font(theme.uiFont(9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text(group.title).font(theme.uiFont(11, weight: .semibold))
                Text("\(group.tasks.count)").font(theme.metadataFont(9)).foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(width: contentWidth, height: 32)
        .background(theme.ink.opacity(0.07))
        .accessibilityLabel("\(group.title), \(group.tasks.count) tasks")
        .accessibilityValue(collapsedGroups.contains(group.id) ? "Collapsed" : "Expanded")
    }

    private var contentWidth: CGFloat {
        CGFloat(model.tableTaskColumnWidth) + statusWidth + teamWidth + checklistWidth + deadlineWidth + 72
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Task").frame(width: CGFloat(model.tableTaskColumnWidth), alignment: .leading)
            Text("Status").frame(width: statusWidth, alignment: .leading)
            Text("Team").frame(width: teamWidth, alignment: .leading)
            Text("Checklist").frame(width: checklistWidth, alignment: .leading)
            Text("Deadline").frame(width: deadlineWidth, alignment: .leading)
        }
        .font(theme.uiFont(10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(width: contentWidth, height: 36, alignment: .leading)
        .background(theme.isSystem ? Color(nsColor: .controlBackgroundColor) : theme.surface)
    }

    private func tableRow(_ task: TaskItem) -> some View {
        Button { model.selectedTaskID = task.id } label: {
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Button { model.toggleTask(task) } label: {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.status == .done ? OwnwardTheme.success : .secondary)
                    }.buttonStyle(.plain)
                    Text(task.title).font(theme.uiFont(12, weight: .medium)).lineLimit(1)
                }
                .frame(width: CGFloat(model.tableTaskColumnWidth), alignment: .leading)

                Text(task.status.title).frame(width: statusWidth, alignment: .leading)
                Text(task.team ?? "—").frame(width: teamWidth, alignment: .leading)
                Text(task.miniTasks.isEmpty ? "—" : "\(task.completedMiniTaskCount)/\(task.miniTasks.count)")
                    .font(theme.metadataFont(10)).frame(width: checklistWidth, alignment: .leading)
                Text((task.deadlineEnd ?? task.deadlineStart)?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                    .foregroundStyle(isOverdue(task) ? OwnwardTheme.destructive : .primary)
                    .frame(width: deadlineWidth, alignment: .leading)
            }
            .font(theme.uiFont(11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(width: contentWidth, height: 42, alignment: .leading)
            .background(model.selectedTaskID == task.id ? theme.accent.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        if collapsedGroups.contains(id) { collapsedGroups.remove(id) }
        else { collapsedGroups.insert(id) }
    }

    private func isOverdue(_ task: TaskItem) -> Bool {
        guard task.status != .done,
              task.status != .discarded,
              let dueDate = task.deadlineEnd ?? task.deadlineStart else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date())
    }
}
