import Foundation

public enum AppThemeChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case paperLight = "paper_light"
    case paperDark = "paper_dark"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: "Apple System"
        case .paperLight: "Paper Light"
        case .paperDark: "Paper Dark"
        }
    }

    public var usesSystemAppearance: Bool { self == .system }
    public var fontFamily: AppFontFamily { usesSystemAppearance ? .system : .ubuntu }

    public var surfaceHex: UInt32? {
        switch self {
        case .system: nil
        case .paperLight: 0xF0EAD8
        case .paperDark: 0x1D1D1B
        }
    }

    public var inkHex: UInt32? {
        switch self {
        case .system: nil
        case .paperLight: 0x1D1D1B
        case .paperDark: 0xF0EAD8
        }
    }

    public var accentHex: UInt32? {
        switch self {
        case .system: nil
        case .paperLight: 0xCCCCCC
        case .paperDark: 0x777777
        }
    }
}

public enum AppFontFamily: String, Codable, Sendable {
    case system
    case ubuntu
}

public enum ZoomLevel {
    public static let minimum = 0.7
    public static let maximum = 1.5
    public static let step = 0.1

    public static func increased(from value: Double) -> Double { adjusted(value + step) }
    public static func decreased(from value: Double) -> Double { adjusted(value - step) }

    private static func adjusted(_ value: Double) -> Double {
        min(maximum, max(minimum, (value * 10).rounded() / 10))
    }
}

public enum TableTaskColumnWidth {
    public static let minimum = 190.0
    public static let maximum = 520.0
    public static let defaultValue = 260.0

    public static func clamped(_ value: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

public struct WindowDimensions: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum WindowSizePolicy {
    public static let minimum = WindowDimensions(width: 760, height: 500)
    public static let preferred = WindowDimensions(width: 1240, height: 800)

    /// Leaves a small margin around the initial window on compact displays while
    /// keeping a comfortable desktop-sized canvas on larger screens.
    public static func defaultSize(in visibleSize: WindowDimensions) -> WindowDimensions {
        WindowDimensions(
            width: min(preferred.width, max(minimum.width, visibleSize.width * 0.92)),
            height: min(preferred.height, max(minimum.height, visibleSize.height * 0.90))
        )
    }

    public static func shouldClampLegacyWindow(_ size: WindowDimensions) -> Bool {
        size.width > preferred.width || size.height > preferred.height
    }
}
