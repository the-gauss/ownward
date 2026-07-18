import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var theme: OwnwardTheme { OwnwardTheme(choice: model.themeChoice) }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 250, max: 310)
        } detail: {
            MainContentView(model: model)
                .inspector(isPresented: inspectorBinding) {
                    if let task = model.selectedTask {
                        InspectorView(model: model, task: task)
                            .id(task.id)
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 430)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .ownwardAppearance(theme)
        .onAppear { OwnwardAppearanceCoordinator.apply(model.themeChoice) }
        .onChange(of: model.themeChoice) { _, choice in
            OwnwardAppearanceCoordinator.apply(choice)
        }
        .onChange(of: model.sidebarSelection) { _, selection in
            model.selectedTaskID = nil
            if case .saved = selection { model.viewMode = .table }
        }
        .alert("Ownward API", isPresented: Binding(get: { model.apiError != nil }, set: { if !$0 { model.apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.apiError ?? "")
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { model.selectedTaskID != nil },
            set: { if !$0 { model.selectedTaskID = nil } }
        )
    }
}
