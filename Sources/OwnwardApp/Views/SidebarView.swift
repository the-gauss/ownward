import SwiftUI
import OwnwardCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingBoard = false
    @State private var newBoardName = ""
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
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
        }
        .listStyle(.sidebar)
        .font(theme.uiFont(13))
        .scrollContentBackground(.hidden)
        .background(theme.isSystem ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.surface))
        .safeAreaInset(edge: .top) {
            HStack {
                OwnwardWordmark()
                Spacer()
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
                    Section("Zoom") {
                        Button("Zoom In") { model.zoomIn() }
                        Button("Zoom Out") { model.zoomOut() }
                        Button("Actual Size") { model.resetZoom() }
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

    private func createBoard() {
        let name = newBoardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.createBoard(named: name)
        newBoardName = ""
        isAddingBoard = false
    }
}
