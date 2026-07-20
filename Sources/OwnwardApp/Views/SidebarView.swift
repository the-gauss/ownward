import SwiftUI
import OwnwardCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingBoard = false
    @State private var newBoardName = ""
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        Group {
            if model.workspaceMode == .projectManagement {
                projectList
            } else {
                jobSearchList
            }
        }
        .listStyle(.sidebar)
        .font(theme.uiFont(13))
        .scrollContentBackground(.hidden)
        .background(theme.isSystem ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.surface))
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    OwnwardWordmark()
                    Spacer()
                }
                Picker("Workspace", selection: $model.workspaceMode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Ownward mode")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(theme.isSystem ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.surface))
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .lineLimit(1)
                Spacer()
                Menu {
                    Section("Appearance") {
                        ForEach(AppThemeChoice.allCases) { choice in
                            Button {
                                model.themeChoice = choice
                            } label: {
                                if model.themeChoice == choice { Label(choice.title, systemImage: "checkmark") }
                                else { Text(choice.title) }
                            }
                        }
                    }
                    if model.workspaceMode.supportsProjectControls {
                        Section("Zoom") {
                            Button("Zoom In") { model.zoomIn() }
                            Button("Zoom Out") { model.zoomOut() }
                            Button("Actual Size") { model.resetZoom() }
                        }
                    }
                } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(theme.uiFont(12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.isSystem ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.surface))
        }
    }

    private var projectList: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                ForEach(model.snapshot.boards) { board in
                    Label(board.name, systemImage: "rectangle.split.3x1")
                        .tag(SidebarSelection.board(board.id))
                }
            } header: {
                HStack {
                    Text("Boards")
                    Spacer()
                    Button { isAddingBoard = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .help("Add Board")
                        .popover(isPresented: $isAddingBoard, arrowEdge: .trailing) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("New Board").font(theme.uiFont(15, weight: .semibold))
                                TextField("Board name", text: $newBoardName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { createBoard() }
                                HStack {
                                    Spacer()
                                    Button("Cancel") { isAddingBoard = false }
                                    Button("Create") { createBoard() }
                                        .keyboardShortcut(.defaultAction)
                                        .disabled(newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(16)
                            .frame(width: 280)
                        }
                }
            }
            Section("Views") {
                ForEach(SavedView.allCases) { view in
                    Label(view.title, systemImage: view.systemImage)
                        .foregroundStyle(view == .discarded ? OwnwardTheme.destructive : .primary)
                        .tag(SidebarSelection.saved(view))
                }
            }
            Section("Daily Log") {
                Label("Daily Log", systemImage: "text.book.closed")
                    .tag(SidebarSelection.dailyLog)
            }
        }
    }

    private var jobSearchList: some View {
        List(selection: $model.jobSidebarSelection) {
            Section("Opportunities") {
                ForEach(JobSearchScope.allCases) { scope in
                    HStack(spacing: 8) {
                        Label(scope.title, systemImage: systemImage(for: scope))
                        Spacer(minLength: 8)
                        Text("\(model.jobRoleCount(for: scope))")
                            .font(theme.metadataFont(10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(JobSearchSidebarSelection.scope(scope))
                }
            }
            Section("Contacts") {
                HStack(spacing: 8) {
                    Label("Contacts Directory", systemImage: "person.2")
                    Spacer(minLength: 8)
                    Text("\(model.jobSearchContactCount)")
                        .font(theme.metadataFont(10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(JobSearchSidebarSelection.contactsDirectory)
            }
            Section("Weekly Log") {
                Label("Weekly Log", systemImage: "text.book.closed")
                    .tag(JobSearchSidebarSelection.weeklyLog)
            }
        }
    }

    private func systemImage(for scope: JobSearchScope) -> String {
        switch scope {
        case .all: "briefcase"
        case .needsAction: "arrow.up.right.circle"
        case .applications: "paperplane"
        case .interviews: "person.2"
        case .followUps: "bell"
        case .closed: "archivebox"
        case .archive: "tray.full"
        }
    }

    private func createBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.createBoard(named: name)
        newBoardName = ""
        isAddingBoard = false
    }
}
