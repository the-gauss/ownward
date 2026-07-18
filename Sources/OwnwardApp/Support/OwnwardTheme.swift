import AppKit
import SwiftUI
import OwnwardCore

struct OwnwardTheme {
    let choice: AppThemeChoice

    static let success = Color(red: 0, green: 200 / 255, blue: 83 / 255)
    static let destructive = Color(red: 1, green: 95 / 255, blue: 56 / 255)

    var isSystem: Bool { choice.usesSystemAppearance }
    var surface: Color { color(hex: choice.surfaceHex) ?? Color(nsColor: .windowBackgroundColor) }
    var ink: Color { color(hex: choice.inkHex) ?? .primary }
    var accent: Color { color(hex: choice.accentHex) ?? .accentColor }
    var panelSurface: Color { isSystem ? Color(nsColor: .controlBackgroundColor) : surface }

    func uiFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard choice.fontFamily == .ubuntu else { return .system(size: size, weight: weight) }
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold: name = "Ubuntu-Bold"
        case .ultraLight, .thin, .light: name = "Ubuntu-Light"
        default: name = "Ubuntu-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    func metadataFont(_ size: CGFloat) -> Font {
        isSystem ? .system(size: size) : .custom("Ubuntu-Regular", fixedSize: size)
    }

    func statusTint(_ status: TaskStatus) -> Color {
        switch status {
        case .toDo: .yellow
        case .inProgress: .blue
        case .done: Self.success
        case .paused: .orange
        case .discarded: .gray
        }
    }

    private func color(hex: UInt32?) -> Color? {
        guard let hex else { return nil }
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct OwnwardThemeKey: EnvironmentKey {
    static let defaultValue = OwnwardTheme(choice: .system)
}

extension EnvironmentValues {
    var ownwardTheme: OwnwardTheme {
        get { self[OwnwardThemeKey.self] }
        set { self[OwnwardThemeKey.self] = newValue }
    }
}

extension AppThemeChoice {
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: nil
        case .paperLight: .light
        case .paperDark: .dark
        }
    }
}

private struct OwnwardAppearanceModifier: ViewModifier {
    let theme: OwnwardTheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme.isSystem {
            content
                .id(theme.choice)
        } else {
            content
                .font(theme.uiFont(13))
                .foregroundStyle(theme.ink)
                .tint(theme.accent)
                .background(theme.surface)
                .id(theme.choice)
        }
    }
}

@MainActor
enum OwnwardAppearanceCoordinator {
    static func apply(_ choice: AppThemeChoice) {
        let appearance: NSAppearance?
        let chromeColor: NSColor
        switch choice {
        case .system:
            appearance = nil
            chromeColor = .windowBackgroundColor
        case .paperLight:
            appearance = NSAppearance(named: .aqua)
            chromeColor = NSColor(red: 240 / 255, green: 234 / 255, blue: 216 / 255, alpha: 1)
        case .paperDark:
            appearance = NSAppearance(named: .darkAqua)
            chromeColor = NSColor(red: 29 / 255, green: 29 / 255, blue: 27 / 255, alpha: 1)
        }

        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
            window.titlebarAppearsTransparent = !choice.usesSystemAppearance
            window.backgroundColor = chromeColor
        }
        OwnwardBrand.applyAppIcon(for: choice)
    }
}

extension View {
    func ownwardAppearance(_ theme: OwnwardTheme) -> some View {
        environment(\.ownwardTheme, theme)
            .modifier(OwnwardAppearanceModifier(theme: theme))
    }
}
