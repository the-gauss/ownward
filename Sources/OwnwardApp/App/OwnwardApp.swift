import AppKit
import SwiftUI
import OwnwardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let choice = UserDefaults.standard.string(forKey: "appearanceTheme")
            .flatMap(AppThemeChoice.init(rawValue:)) ?? .system
        OwnwardBrand.applyAppIcon(for: choice)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        let choice = UserDefaults.standard.string(forKey: "appearanceTheme")
            .flatMap(AppThemeChoice.init(rawValue:)) ?? .system
        OwnwardBrand.applyAppIcon(for: choice)
    }
}

@main
struct OwnwardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel?
    @State private var launchErrorMessage: String?

    init() {
        OwnwardBrand.registerFonts()
        do {
            _model = State(initialValue: try AppBootstrap.makeModel())
            _launchErrorMessage = State(initialValue: nil)
        } catch {
            _model = State(initialValue: nil)
            _launchErrorMessage = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup("Ownward") {
            Group {
                if let model {
                    ContentView(model: model)
                } else {
                    launchFailureView
                }
            }
            .frame(
                minWidth: WindowSizePolicy.minimum.width,
                minHeight: WindowSizePolicy.minimum.height
            )
            .background(WindowPlacementGuard())
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect.size
            let size = WindowSizePolicy.defaultSize(in: WindowDimensions(width: visible.width, height: visible.height))
            return WindowPlacement(size: CGSize(width: size.width, height: size.height))
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Task") { model?.createTask() }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(model == nil)
            }
            CommandMenu("Task") {
                Button("Move to To Do") { if let model, let id = model.selectedTaskID { model.move(id, to: .toDo) } }
                    .keyboardShortcut("1", modifiers: [.command, .shift])
                    .disabled(model == nil)
                Button("Move to In Progress") { if let model, let id = model.selectedTaskID { model.move(id, to: .inProgress) } }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                    .disabled(model == nil)
                Button("Mark Done") { if let model, let task = model.selectedTask { model.toggleTask(task) } }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                    .disabled(model == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { model?.zoomIn() }
                    .keyboardShortcut("+", modifiers: [.command])
                    .disabled(model == nil)
                Button("Zoom Out") { model?.zoomOut() }
                    .keyboardShortcut("-", modifiers: [.command])
                    .disabled(model == nil)
                Button("Actual Size") { model?.resetZoom() }
                    .keyboardShortcut("0", modifiers: [.command])
                    .disabled(model == nil)
                Divider()
                Menu("Appearance") {
                    ForEach(AppThemeChoice.allCases) { choice in
                        Button {
                            model?.themeChoice = choice
                        } label: {
                            if model?.themeChoice == choice { Label(choice.title, systemImage: "checkmark") }
                            else { Text(choice.title) }
                        }
                    }
                }
                .disabled(model == nil)
            }
        }
    }

    private var launchFailureView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Ownward Couldn't Open Its Workspace",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(launchErrorMessage ?? "An unexpected startup error occurred.")
            )
            Button("Try Again", action: retryBootstrap)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in
            retryBootstrap()
        }
    }

    private func retryBootstrap() {
        do {
            let recovered = try AppBootstrap.makeModel()
            model = recovered
            launchErrorMessage = nil
        } catch {
            launchErrorMessage = error.localizedDescription
        }
    }
}
