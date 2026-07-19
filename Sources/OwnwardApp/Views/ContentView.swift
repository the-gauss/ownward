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
            ZStack {
                if !theme.isSystem {
                    theme.surface.ignoresSafeArea()
                }
                Group {
                    switch model.workspaceMode {
                    case .projectManagement:
                        if model.isDailyLogSelected {
                            ScheduledLogView(kind: .dailyDayStarter, entries: model.scheduledLogs(for: .dailyDayStarter))
                                .environment(\.ownwardTheme, theme.scalingFonts(by: model.zoomScale))
                        } else {
                            MainContentView(model: model)
                                .environment(\.ownwardTheme, theme.scalingFonts(by: model.zoomScale))
                        }
                    case .jobSearch:
                        if model.isWeeklyLogSelected {
                            ScheduledLogView(kind: .weeklyCanadaRolesSearch, entries: model.scheduledLogs(for: .weeklyCanadaRolesSearch))
                        } else {
                            JobSearchView(model: model)
                        }
                    }
                }
            }
            .inspector(isPresented: inspectorBinding) {
                    if model.workspaceMode == .projectManagement, !model.isDailyLogSelected, let task = model.selectedTask {
                        InspectorView(model: model, task: task)
                            .id(task.id)
                            .environment(\.ownwardTheme, theme.scalingFonts(by: model.zoomScale))
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 430)
                    } else if model.workspaceMode == .jobSearch, !model.isWeeklyLogSelected, let role = model.selectedJobRole {
                        JobRoleInspectorView(model: model, role: role)
                            .id(role.id)
                            .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(theme.surface, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .animation(.easeInOut(duration: 0.18), value: columnVisibility)
        .ownwardAppearance(theme)
        .onAppear { OwnwardAppearanceCoordinator.apply(model.themeChoice) }
        .onChange(of: model.themeChoice) { _, choice in
            OwnwardAppearanceCoordinator.apply(choice)
        }
        .onChange(of: model.sidebarSelection) { _, selection in
            model.selectedTaskID = nil
            model.resetTaskFilters()
            if case .saved = selection { model.viewMode = .table }
        }
        .onChange(of: model.jobSidebarSelection) { _, _ in
            if let selected = model.selectedJobRoleID,
               !model.visibleJobRoles.contains(where: { $0.id == selected }) {
                model.selectedJobRoleID = nil
            }
        }
        .alert("Ownward", isPresented: Binding(get: { model.apiError != nil }, set: { if !$0 { model.apiError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.apiError ?? "")
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: {
                switch model.workspaceMode {
                case .projectManagement: !model.isDailyLogSelected && model.selectedTaskID != nil
                case .jobSearch: !model.isWeeklyLogSelected && model.selectedJobRoleID != nil
                }
            },
            set: { presented in
                guard !presented else { return }
                switch model.workspaceMode {
                case .projectManagement: model.selectedTaskID = nil
                case .jobSearch: model.selectedJobRoleID = nil
                }
            }
        )
    }
}
