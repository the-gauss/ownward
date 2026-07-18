import AppKit
import SwiftUI
import OwnwardCore

/// Applies the compact-window migration once. SwiftUI restores the previous
/// frame before `defaultWindowPlacement` runs, so legacy 1488×960 windows need
/// a one-time correction even though all future windows use the adaptive size.
struct WindowPlacementGuard: NSViewRepresentable {
    private static let migrationKey = "adaptiveWindowSizeV2Applied"

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        guard !context.coordinator.hasApplied else { return }
        context.coordinator.hasApplied = true
        DispatchQueue.main.async {
            guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: Self.migrationKey) {
                let content = window.contentLayoutRect.size
                let current = WindowDimensions(width: content.width, height: content.height)
                if WindowSizePolicy.shouldClampLegacyWindow(current) {
                    let visible = screen.visibleFrame.size
                    let target = WindowSizePolicy.defaultSize(
                        in: WindowDimensions(width: visible.width, height: visible.height)
                    )
                    window.setContentSize(CGSize(width: target.width, height: target.height))
                    window.center()
                }
                defaults.set(true, forKey: Self.migrationKey)
            }
            if !screen.visibleFrame.contains(window.frame) {
                window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: true)
            }
        }
    }

    final class Coordinator {
        var hasApplied = false
    }
}
