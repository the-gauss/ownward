import AppKit
import SwiftUI
import OwnwardCore

struct InspectorView: View {
    @Bindable var model: AppModel
    let task: TaskItem
    @State private var draft: TaskItem
    @State private var savedDraft: TaskItem
    @State private var hasDeadline: Bool
    @State private var referenceSource: CompletionTarget
    @State private var referenceTarget: CompletionTarget?
    @State private var showsAllChecklistItems = false
    @State private var isPickingReferenceSource = false
    @State private var isPickingReferenceTarget = false
    @State private var checklistReferenceSource: MiniTaskID?
    @FocusState private var focusedMiniTaskID: MiniTaskID?
    @Environment(\.ownwardTheme) private var theme

    init(model: AppModel, task: TaskItem) {
        self.model = model
        self.task = task
        _draft = State(initialValue: task)
        _savedDraft = State(initialValue: task)
        _hasDeadline = State(initialValue: task.deadlineStart != nil || task.deadlineEnd != nil)
        _referenceSource = State(initialValue: .task(task.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button { toggleDraftTask() } label: {
                        Image(systemName: draft.status == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 23))
                            .foregroundStyle(draft.status == .done ? OwnwardTheme.success : .secondary)
                    }.buttonStyle(.plain)
                    TextField("Task title", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(theme.uiFont(16, weight: .semibold))
                    Button { model.selectedTaskID = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(14)
                Divider()

                InspectorSection("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(TaskStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().tint(.primary)
                }

                InspectorSection("Team") {
                    TaskTeamPicker(
                        selection: teamBinding,
                        teams: model.teams(for: draft)
                    ) { name in
                        let canonicalName = model.canonicalTeamName(name, for: draft.boardID)
                        draft.team = canonicalName
                        model.createTeam(named: canonicalName, on: draft.boardID)
                    }
                }

                InspectorSection("Deadline") {
                    Toggle("Scheduled", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Start", selection: startDateBinding, displayedComponents: .date)
                        Toggle("Date range", isOn: endDateEnabledBinding)
                        if draft.deadlineEnd != nil {
                            DatePicker("End", selection: endDateBinding, displayedComponents: .date)
                        }
                    }
                }

                InspectorSection("Checklist", trailing: "\(draft.completedMiniTaskCount) of \(draft.miniTasks.count)") {
                    if !draft.miniTasks.isEmpty {
                        ProgressView(value: Double(draft.completedMiniTaskCount), total: Double(draft.miniTasks.count))
                            .tint(OwnwardTheme.success)
                    }
                    ForEach(visibleChecklistGroups) { group in
                        if let category = group.category {
                            Text(category)
                                .font(theme.uiFont(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        ForEach(group.items) { mini in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Button { toggle(mini) } label: {
                                    Image(systemName: mini.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(mini.isCompleted ? OwnwardTheme.success : .secondary)
                                }.buttonStyle(.plain)
                                TextField("Checklist item", text: miniTaskTitleBinding(for: mini))
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .font(theme.uiFont(12))
                                    .strikethrough(mini.isCompleted, color: .secondary)
                                    .foregroundStyle(mini.isCompleted ? .secondary : .primary)
                                    .focused($focusedMiniTaskID, equals: mini.id)
                                    .onSubmit(save)
                                    .frame(maxWidth: .infinity)
                                Button {
                                    addSubtask(to: mini)
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Add sub-task")
                                .help("Add sub-task")
                                Button {
                                    checklistReferenceSource = mini.id
                                } label: {
                                    Image(systemName: "arrow.triangle.branch")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Reference checklist item")
                                .help("Reference completion")
                                .popover(isPresented: checklistReferenceBinding(for: mini.id), arrowEdge: .trailing) {
                                    ReferenceTargetPicker(
                                        title: "Reference Completion",
                                        suggested: referenceSuggestions(for: .miniTask(mini.id)),
                                        searchOptions: referenceCandidates(excluding: .miniTask(mini.id)),
                                        label: targetLabel
                                    ) { selected in
                                        model.addReference(from: .miniTask(mini.id), to: selected)
                                        checklistReferenceSource = nil
                                    }
                                }
                                Button(role: .destructive) {
                                    delete(mini)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(OwnwardTheme.destructive)
                                .accessibilityLabel("Delete checklist item")
                                .help("Delete item and its sub-tasks")
                            }
                            .padding(.leading, CGFloat(mini.depth * 14))
                        }
                    }
                    if draft.miniTasks.count > 8 {
                        Button(checklistVisibilityTitle) {
                            withAnimation(.easeInOut(duration: 0.18)) { showsAllChecklistItems.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(theme.uiFont(11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Button { addMiniTask() } label: { Label("Add Item", systemImage: "plus") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }

                InspectorSection("Notes") {
                    TextEditor(text: $draft.notesMarkdown)
                        .font(theme.uiFont(12))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(6)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                if !draft.links.isEmpty {
                    InspectorSection("Links") {
                        ForEach(draft.links) { link in
                            Button { if let url = URL(string: link.url) { NSWorkspace.shared.open(url) } } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "link")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(link.title).lineLimit(2)
                                        Text(link.url).font(theme.uiFont(9)).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }

                InspectorSection("References") {
                    LabeledContent("Source") {
                        Button {
                            isPickingReferenceSource = true
                        } label: {
                            CompactPickerLabel(title: targetLabel(referenceSource))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isPickingReferenceSource, arrowEdge: .trailing) {
                            ReferenceTargetPicker(
                                title: "Reference Source",
                                suggested: Array(currentTaskTargets.prefix(3)),
                                searchOptions: currentTaskTargets,
                                label: targetLabel
                            ) { selected in
                                referenceSource = selected
                                referenceTarget = nil
                                isPickingReferenceSource = false
                            }
                        }
                    }
                    LabeledContent("Referenced item") {
                        Button {
                            isPickingReferenceTarget = true
                        } label: {
                            CompactPickerLabel(title: referenceTarget.map(targetLabel) ?? "Choose an item")
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isPickingReferenceTarget, arrowEdge: .trailing) {
                            ReferenceTargetPicker(
                                title: "Referenced Item",
                                suggested: referenceSuggestions(for: referenceSource),
                                searchOptions: referenceCandidates(excluding: referenceSource),
                                label: targetLabel
                            ) { selected in
                                referenceTarget = selected
                                isPickingReferenceTarget = false
                            }
                        }
                    }
                    Button("Reference Completion") {
                        if let referenceTarget { model.addReference(from: referenceSource, to: referenceTarget) }
                    }
                    .disabled(referenceTarget == nil)
                    let members = model.referenceMembers(for: referenceSource)
                    if !members.isEmpty {
                        Text("Completion is shared with \(members.count - 1) other item\(members.count == 2 ? "" : "s").")
                            .font(theme.uiFont(10)).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Created \(draft.createdAt.formatted(date: .numeric, time: .shortened))")
                        Text("Updated \(draft.updatedAt.formatted(date: .numeric, time: .shortened))")
                    }
                    .font(theme.metadataFont(9)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { save() }.keyboardShortcut("s", modifiers: [.command])
                }
                .padding(14)
            }
        }
        .background(theme.isSystem ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(theme.surface))
        .background {
            InspectorScheduleSynchronizer(task: task, draft: $draft, savedDraft: $savedDraft, hasDeadline: $hasDeadline)
        }
        .onDisappear { save() }
    }

    private var checklistVisibilityTitle: String {
        showsAllChecklistItems ? "Show Less" : "Show \(draft.miniTasks.count - 8) More"
    }

    private var startDateBinding: Binding<Date> {
        Binding(get: { draft.deadlineStart ?? Date() }, set: { draft.deadlineStart = $0 })
    }
    private var teamBinding: Binding<String?> {
        Binding(
            get: { draft.team },
            set: { value in
                let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.team = normalized?.isEmpty == false ? normalized : nil
            }
        )
    }
    private var endDateBinding: Binding<Date> {
        Binding(get: { draft.deadlineEnd ?? draft.deadlineStart ?? Date() }, set: { draft.deadlineEnd = $0 })
    }
    private var endDateEnabledBinding: Binding<Bool> {
        Binding(get: { draft.deadlineEnd != nil }, set: { draft.deadlineEnd = $0 ? (draft.deadlineStart ?? Date()) : nil })
    }
    private var currentTaskTargets: [CompletionTarget] {
        [.task(draft.id)] + draft.miniTasks.map { .miniTask($0.id) }
    }
    private var visibleChecklistItems: ArraySlice<MiniTask> {
        showsAllChecklistItems ? draft.miniTasks[...] : draft.miniTasks.prefix(8)
    }
    private var visibleChecklistGroups: [ChecklistCategoryGroup] {
        ChecklistOrganizer.grouped(visibleChecklistItems)
    }
    private var allTargets: [CompletionTarget] {
        model.snapshot.tasks.flatMap { task in [.task(task.id)] + task.miniTasks.map { .miniTask($0.id) } }
    }

    private func referenceCandidates(excluding source: CompletionTarget) -> [CompletionTarget] { allTargets.filter { $0 != source } }

    private func referenceSuggestions(for source: CompletionTarget) -> [CompletionTarget] {
        return referenceCandidates(excluding: source)
            .compactMap { candidate -> (target: CompletionTarget, score: Int)? in
                let score = ReferenceSuggestionRanker.score(
                    sourceTitle: targetTitle(source),
                    candidateTitle: targetTitle(candidate)
                )
                return score > 0 ? (candidate, score) : nil
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? targetLabel(lhs.target).localizedStandardCompare(targetLabel(rhs.target)) == .orderedAscending
                    : lhs.score > rhs.score
            }
            .prefix(3)
            .map(\.target)
    }

    private func targetLabel(_ target: CompletionTarget) -> String {
        switch target {
        case .task(let id):
            guard let task = model.snapshot.task(id: id) else { return "Unknown task" }
            return "\(boardName(for: task)) › \(task.title)"
        case .miniTask(let id):
            guard let mini = model.snapshot.miniTask(id: id),
                  let task = model.snapshot.task(id: mini.taskID) else { return "Unknown mini-task" }
            return "\(boardName(for: task)) › \(task.title) › \(mini.title)"
        }
    }

    private func targetTitle(_ target: CompletionTarget) -> String {
        switch target {
        case .task(let id): return model.snapshot.task(id: id)?.title ?? ""
        case .miniTask(let id): return model.snapshot.miniTask(id: id)?.title ?? ""
        }
    }

    private func boardName(for task: TaskItem) -> String {
        model.snapshot.boards.first(where: { $0.id == task.boardID })?.name ?? "Unknown board"
    }

    private func miniTaskTitleBinding(for mini: MiniTask) -> Binding<String> {
        Binding(
            get: { draft.miniTasks.first(where: { $0.id == mini.id })?.title ?? mini.title },
            set: { title in
                guard let index = draft.miniTasks.firstIndex(where: { $0.id == mini.id }) else { return }
                draft.miniTasks[index].title = title
            }
        )
    }

    private func checklistReferenceBinding(for miniTaskID: MiniTaskID) -> Binding<Bool> {
        Binding(
            get: { checklistReferenceSource == miniTaskID },
            set: { if !$0 { checklistReferenceSource = nil } }
        )
    }
    private func toggle(_ mini: MiniTask) {
        model.toggleMiniTask(mini)
        if let index = draft.miniTasks.firstIndex(where: { $0.id == mini.id }) { draft.miniTasks[index].isCompleted.toggle() }
    }
    private func toggleDraftTask() {
        model.toggleTask(draft)
        if draft.status == .done {
            draft.status = draft.previousActiveStatus ?? .toDo
        } else {
            if draft.status != .discarded { draft.previousActiveStatus = draft.status }
            draft.status = .done
        }
    }
    private func addMiniTask() {
        let mini = ChecklistEditor.addItem(to: &draft)
        showsAllChecklistItems = true
        save()
        DispatchQueue.main.async { focusedMiniTaskID = mini.id }
    }
    private func addSubtask(to mini: MiniTask) {
        do {
            let subtask = try ChecklistEditor.addSubtask(to: mini.id, in: &draft)
            showsAllChecklistItems = true
            save()
            DispatchQueue.main.async { focusedMiniTaskID = subtask.id }
        } catch {
            model.apiError = error.localizedDescription
        }
    }
    private func delete(_ mini: MiniTask) {
        do {
            let removedIDs = try ChecklistEditor.removeItem(mini.id, from: &draft)
            if let focusedMiniTaskID, removedIDs.contains(focusedMiniTaskID) {
                self.focusedMiniTaskID = nil
            }
            if let checklistReferenceSource, removedIDs.contains(checklistReferenceSource) {
                self.checklistReferenceSource = nil
            }
            save()
        } catch {
            model.apiError = error.localizedDescription
        }
    }
    private func save() {
        var taskToSave = draft
        if !hasDeadline { taskToSave.deadlineStart = nil; taskToSave.deadlineEnd = nil }
        guard taskToSave != savedDraft else { return }
        draft = taskToSave
        savedDraft = taskToSave
        model.updateTask(taskToSave)
    }
}

private struct InspectorScheduleSynchronizer: View {
    let task: TaskItem
    @Binding var draft: TaskItem
    @Binding var savedDraft: TaskItem
    @Binding var hasDeadline: Bool

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: task.deadlineStart) { _, start in
                synchronize(start: start, end: task.deadlineEnd)
            }
            .onChange(of: task.deadlineEnd) { _, end in
                synchronize(start: task.deadlineStart, end: end)
            }
    }

    private func synchronize(start: Date?, end: Date?) {
        draft.deadlineStart = start
        draft.deadlineEnd = end
        savedDraft.deadlineStart = start
        savedDraft.deadlineEnd = end
        hasDeadline = start != nil || end != nil
    }
}

private struct CompactPickerLabel: View {
    let title: String
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
        }
        .font(theme.uiFont(11))
        .padding(.horizontal, 8)
        .frame(width: 180, height: 25)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).stroke(.separator.opacity(0.6)) }
    }
}

private struct TaskTeamPicker: View {
    @Binding var selection: String?
    let teams: [String]
    let onCreate: (String) -> Void
    @State private var isCreatingTeam = false
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var normalizedDraftName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Menu {
            Button {
                draftName = ""
                isCreatingTeam = true
            } label: {
                Label("Create Team", systemImage: "plus")
            }
            Divider()
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("No Team", systemImage: "checkmark")
                } else {
                    Text("No Team")
                }
            }
            ForEach(teams, id: \.self) { team in
                Button {
                    selection = team
                } label: {
                    selection?.caseInsensitiveCompare(team) == .orderedSame
                        ? Label(team, systemImage: "checkmark")
                        : Label(team, systemImage: "circle")
                }
            }
        } label: {
            CompactPickerLabel(title: selection ?? "No Team")
        }
        .menuStyle(.borderlessButton)
        .popover(isPresented: $isCreatingTeam, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create Team")
                    .font(.headline)
                TextField("Team name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(createTeam)
                HStack {
                    Spacer()
                    Button("Cancel") { isCreatingTeam = false }
                    Button("Create", action: createTeam)
                        .keyboardShortcut(.defaultAction)
                        .disabled(normalizedDraftName.isEmpty)
                }
            }
            .padding(14)
            .frame(width: 240)
            .onAppear { isNameFocused = true }
        }
        .accessibilityLabel("Team")
    }

    private func createTeam() {
        guard !normalizedDraftName.isEmpty else { return }
        selection = normalizedDraftName
        onCreate(normalizedDraftName)
        isCreatingTeam = false
    }
}

private struct ReferenceTargetPicker: View {
    let title: String
    let suggested: [CompletionTarget]
    let searchOptions: [CompletionTarget]
    let label: (CompletionTarget) -> String
    let onSelect: (CompletionTarget) -> Void
    @State private var searchText = ""
    @Environment(\.ownwardTheme) private var theme

    private var searchResults: [CompletionTarget] {
        searchOptions.filter { label($0).localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(theme.uiFont(14, weight: .semibold))
            TextField("Search tasks and mini-tasks", text: $searchText)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if searchText.isEmpty {
                        if suggested.isEmpty {
                            Text("No close matches. Search every board to find an item.")
                                .font(theme.uiFont(11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                        } else {
                            Text("Suggested")
                                .font(theme.uiFont(10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 2)
                            targetButtons(suggested)
                        }
                    } else if searchResults.isEmpty {
                        Text("No matching tasks or checklist items.")
                            .font(theme.uiFont(11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        targetButtons(searchResults)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: 220)
        .background(theme.isSystem ? Color.clear : theme.surface)
    }

    @ViewBuilder
    private func targetButtons(_ targets: [CompletionTarget]) -> some View {
        ForEach(targets, id: \.rawID) { target in
            Button {
                onSelect(target)
            } label: {
                Text(label(target))
                    .font(theme.uiFont(11))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: Content
    @Environment(\.ownwardTheme) private var theme

    init(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(theme.uiFont(12, weight: .semibold))
                Spacer()
                if let trailing { Text(trailing).font(theme.metadataFont(9)).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(14)
        Divider()
    }
}
