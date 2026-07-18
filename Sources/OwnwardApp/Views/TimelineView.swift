import AppKit
import SwiftUI
import OwnwardCore

struct TimelineView: View {
    @Bindable var model: AppModel
    @State private var focusedDate: Date?
    @Environment(\.ownwardTheme) private var theme
    private let calendar = Calendar.current
    private let dayWidth: CGFloat = 34
    private let labelWidth: CGFloat = 164
    private let headerHeight: CGFloat = 62
    private let groupHeight: CGFloat = 30
    private let taskHeight: CGFloat = 52

    private var datedTasks: [TaskItem] {
        model.visibleTasks.filter { $0.deadlineStart != nil || $0.deadlineEnd != nil }
    }

    private var groups: [TaskGroup] {
        TaskOrganizer.grouped(datedTasks, by: model.timelineGrouping).map {
            TaskGroup(title: $0.title, tasks: $0.tasks.sorted(by: startDateOrder))
        }
    }

    private var rows: [TimelineRow] {
        if model.timelineGrouping == .none {
            return datedTasks.sorted(by: startDateOrder).map(TimelineRow.task)
        }
        return groups.flatMap { group in
            [.group(group.title, group.tasks.count)] + group.tasks.map(TimelineRow.task)
        }
    }

    private var scale: TimelineScale? {
        let dates = datedTasks.flatMap { [$0.deadlineStart, $0.deadlineEnd].compactMap { $0 } }
        guard let minimum = dates.min(), let maximum = dates.max() else { return nil }
        let today = calendar.startOfDay(for: Date())
        let boundedMinimum = min(minimum, today)
        let boundedMaximum = max(maximum, today)
        return TimelineScale(
            start: calendar.date(byAdding: .day, value: -1, to: boundedMinimum) ?? boundedMinimum,
            end: calendar.date(byAdding: .day, value: 2, to: boundedMaximum) ?? boundedMaximum,
            calendar: calendar
        )
    }

    var body: some View {
        Group {
            if let scale {
                VStack(spacing: 0) {
                    timelineToolbar(scale)
                    Divider()
                    GeometryReader { geometry in
                        ScrollView(.vertical) {
                            HStack(alignment: .top, spacing: 0) {
                                labelColumn
                                Divider()
                                ScrollView(.horizontal) {
                                    chart(scale)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scrollPosition(id: $focusedDate, anchor: .center)
                            }
                            .frame(width: geometry.size.width, alignment: .leading)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No scheduled tasks", systemImage: "calendar", description: Text("Add a start date or deadline to place a task on the timeline."))
            }
        }
        .background(theme.isSystem ? Color(nsColor: .controlBackgroundColor).opacity(0.45) : theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)) }
    }

    private func timelineToolbar(_ scale: TimelineScale) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
            Text(scale.start.formatted(.dateTime.month(.wide).year()))
                .font(theme.uiFont(12, weight: .semibold))
            Text("–")
            Text(scale.end.formatted(.dateTime.month(.wide).year()))
                .font(theme.uiFont(12, weight: .semibold))
            Spacer()
            Text("\(datedTasks.count) scheduled")
                .font(theme.uiFont(10))
                .foregroundStyle(.secondary)
            Button("Today") { focusedDate = calendar.startOfDay(for: Date()) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var labelColumn: some View {
        LazyVStack(spacing: 0) {
            HStack {
                Text("Task").font(theme.uiFont(10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: labelWidth, height: headerHeight)
            .background(theme.ink.opacity(0.04))

            ForEach(rows) { row in
                switch row {
                case .group(let title, let count):
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        Text(title).font(theme.uiFont(10, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(count)").font(theme.metadataFont(9)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: labelWidth, height: groupHeight)
                    .background(theme.ink.opacity(0.075))
                case .task(let task):
                    Button { model.selectedTaskID = task.id } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(theme.uiFont(11, weight: .medium)).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(task.team ?? "No Team").lineLimit(1)
                                if !task.miniTasks.isEmpty {
                                    Text("· \(task.completedMiniTaskCount)/\(task.miniTasks.count)")
                                }
                            }
                            .font(theme.uiFont(8.5))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .frame(width: labelWidth, height: taskHeight)
                        .contentShape(Rectangle())
                        .background(model.selectedTaskID == task.id ? theme.accent.opacity(0.12) : .clear)
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
        }
        .frame(width: labelWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chart(_ scale: TimelineScale) -> some View {
        let width = CGFloat(scale.totalDays) * dayWidth
        return LazyVStack(spacing: 0) {
            dateHeader(scale)
            ForEach(rows) { row in
                switch row {
                case .group:
                    Rectangle().fill(theme.ink.opacity(0.075)).frame(width: width, height: groupHeight)
                case .task(let task):
                    timelineTaskRow(task, scale: scale, width: width)
                }
                Divider()
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func dateHeader(_ scale: TimelineScale) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(monthSegments(scale), id: \.title) { segment in
                    Text(segment.title)
                        .font(theme.uiFont(10, weight: .semibold))
                        .frame(width: CGFloat(segment.days) * dayWidth, alignment: .leading)
                        .padding(.leading, 8)
                }
            }
            .frame(height: 28)
            Divider()
            HStack(spacing: 0) {
                ForEach(days(scale), id: \.self) { date in
                    VStack(spacing: 2) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(theme.uiFont(8))
                        Text(date.formatted(.dateTime.day())).font(theme.metadataFont(9))
                    }
                    .foregroundStyle(calendar.isDateInToday(date) ? OwnwardTheme.destructive : .secondary)
                    .frame(width: dayWidth, height: 33)
                    .background(calendar.isDateInWeekend(date) ? theme.ink.opacity(0.045) : .clear)
                    .overlay(alignment: .trailing) { Divider() }
                    .id(date)
                }
            }
        }
        .frame(height: headerHeight)
        .background(theme.ink.opacity(0.04))
    }

    private func timelineTaskRow(_ task: TaskItem, scale: TimelineScale, width: CGFloat) -> some View {
        let start = task.deadlineStart ?? task.deadlineEnd ?? scale.start
        let end = task.deadlineEnd ?? task.deadlineStart ?? start
        let offset = CGFloat(scale.dayOffset(for: start)) * dayWidth + 4
        let span = scale.spanDays(from: start, through: end)
        let barWidth = max(dayWidth - 8, CGFloat(span) * dayWidth - 8)
        let progress = task.miniTasks.isEmpty ? (task.status == .done ? 1 : 0) : task.checklistProgress

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(days(scale), id: \.self) { date in
                    Rectangle()
                        .fill(calendar.isDateInWeekend(date) ? theme.ink.opacity(0.035) : .clear)
                        .frame(width: dayWidth, height: taskHeight)
                        .overlay(alignment: .trailing) { Divider().opacity(0.55) }
                }
            }
            if scale.dayOffset(for: Date()) >= 0, scale.dayOffset(for: Date()) < scale.totalDays {
                Rectangle()
                    .fill(OwnwardTheme.destructive.opacity(0.75))
                    .frame(width: 1, height: taskHeight)
                    .offset(x: CGFloat(scale.dayOffset(for: Date())) * dayWidth + dayWidth / 2)
            }
            TimelineTaskBar(
                model: model,
                task: task,
                start: start,
                end: end,
                baseOffset: offset,
                baseWidth: barWidth,
                spanDays: span,
                dayWidth: dayWidth,
                progress: progress,
                color: theme.statusTint(task.status)
            )
        }
        .frame(width: width, height: taskHeight, alignment: .leading)
    }

    private func days(_ scale: TimelineScale) -> [Date] {
        (0..<scale.totalDays).compactMap { calendar.date(byAdding: .day, value: $0, to: scale.start) }
    }

    private func monthSegments(_ scale: TimelineScale) -> [MonthSegment] {
        var result: [MonthSegment] = []
        for date in days(scale) {
            let title = date.formatted(.dateTime.month(.wide).year())
            if let lastIndex = result.indices.last, result[lastIndex].title == title {
                result[lastIndex].days += 1
            }
            else { result.append(MonthSegment(title: title, days: 1)) }
        }
        return result
    }

    private func startDateOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        (lhs.deadlineStart ?? lhs.deadlineEnd ?? .distantFuture) < (rhs.deadlineStart ?? rhs.deadlineEnd ?? .distantFuture)
    }
}

private struct TimelineTaskBar: View {
    @Bindable var model: AppModel
    let task: TaskItem
    let start: Date
    let end: Date
    let baseOffset: CGFloat
    let baseWidth: CGFloat
    let spanDays: Int
    let dayWidth: CGFloat
    let progress: Double
    let color: Color
    @Environment(\.ownwardTheme) private var theme
    @State private var editMode: TimelineDragMode?
    @State private var hoveredEdge: TimelineDragMode?
    @State private var translation: CGFloat = 0
    private let calendar = Calendar.current
    private let resizeHandleWidth: CGFloat = 12

    private var dayDelta: Int {
        TimelineDragMath.dayDelta(
            translation: Double(translation),
            dayWidth: Double(dayWidth),
            operation: editMode?.operation ?? .move,
            spanDays: spanDays
        )
    }
    private var previewOffset: CGFloat {
        switch editMode {
        case .move: baseOffset + CGFloat(dayDelta) * dayWidth
        case .resizeStart: baseOffset + CGFloat(dayDelta) * dayWidth
        case .resizeEnd, .none: baseOffset
        }
    }
    private var previewWidth: CGFloat {
        switch editMode {
        case .resizeStart: baseWidth - CGFloat(dayDelta) * dayWidth
        case .resizeEnd: baseWidth + CGFloat(dayDelta) * dayWidth
        case .move, .none: baseWidth
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.22))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.8))
                .frame(width: max(3, previewWidth * progress))
            if previewWidth > 100 {
                Text(task.title)
                    .font(theme.uiFont(10, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: max(dayWidth - 8, previewWidth), height: 30)
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.55)) }
        .overlay(alignment: .leading) { resizeHandle(.resizeStart) }
        .overlay(alignment: .trailing) { resizeHandle(.resizeEnd) }
        .offset(x: previewOffset)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .highPriorityGesture(dragGesture)
        .onTapGesture { model.selectedTaskID = task.id }
        .contextMenu {
            Button("Shift One Day Earlier") { model.shiftTaskDates(task.id, byDays: -1) }
            Button("Shift One Day Later") { model.shiftTaskDates(task.id, byDays: 1) }
            Divider()
            Button("Move Start One Day Earlier") { resize(.start, date: start, byDays: -1) }
            Button("Move Start One Day Later") { resize(.start, date: start, byDays: 1) }
            Button("Move End One Day Earlier") { resize(.end, date: end, byDays: -1) }
            Button("Move End One Day Later") { resize(.end, date: end, byDays: 1) }
        }
        .help("Drag to shift dates. Drag either edge to resize. \(dateRange)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.title), \(dateRange)")
        .accessibilityHint("Drag the bar to shift dates, or drag an edge to change one date.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.selectedTaskID = task.id }
    }

    private func resizeHandle(_ mode: TimelineDragMode) -> some View {
        Capsule()
            .fill(theme.ink.opacity(editMode == mode || hoveredEdge == mode ? 0.5 : 0.2))
            .frame(width: 9, height: 24)
            .contentShape(Rectangle())
            .onHover { inside in
                hoveredEdge = inside ? mode : nil
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let mode = editMode ?? dragMode(at: value.startLocation.x)
                editMode = mode
                translation = value.translation.width
            }
            .onEnded { value in
                let mode = editMode ?? dragMode(at: value.startLocation.x)
                let delta = dayDelta
                switch mode {
                case .move:
                    model.shiftTaskDates(task.id, byDays: delta)
                case .resizeStart:
                    if let date = calendar.date(byAdding: .day, value: delta, to: start) {
                        model.resizeTaskDates(task.id, edge: .start, to: date)
                    }
                case .resizeEnd:
                    if let date = calendar.date(byAdding: .day, value: delta, to: end) {
                        model.resizeTaskDates(task.id, edge: .end, to: date)
                    }
                }
                editMode = nil
                translation = 0
            }
    }

    private func dragMode(at horizontalPosition: CGFloat) -> TimelineDragMode {
        if horizontalPosition <= resizeHandleWidth { return .resizeStart }
        if horizontalPosition >= baseWidth - resizeHandleWidth { return .resizeEnd }
        return .move
    }

    private var dateRange: String {
        "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func resize(_ edge: TimelineEdge, date: Date, byDays days: Int) {
        guard let adjusted = calendar.date(byAdding: .day, value: days, to: date) else { return }
        model.resizeTaskDates(task.id, edge: edge, to: adjusted)
    }
}

private enum TimelineDragMode {
    case move
    case resizeStart
    case resizeEnd

    var operation: TimelineDragOperation {
        switch self {
        case .move: .move
        case .resizeStart: .resizeStart
        case .resizeEnd: .resizeEnd
        }
    }
}

private struct MonthSegment {
    var title: String
    var days: Int
}

private enum TimelineRow: Identifiable {
    case group(String, Int)
    case task(TaskItem)

    var id: String {
        switch self {
        case .group(let title, _): "group-\(title)"
        case .task(let task): "task-\(task.id)"
        }
    }
}
