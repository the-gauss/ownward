import AppKit
import CoreText
import SwiftUI
import OwnwardCore

enum OwnwardBrand {
    static let wordmarkFontName = "ReadexPro-SemiBold"

    static func registerFonts() {
        guard let url = resourceURL(name: "ReadexPro_600SemiBold", extension: "ttf", subdirectory: "Fonts") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    @MainActor
    static func applyAppIcon(for choice: AppThemeChoice) {
        NSApp.applicationIconImage = iconImage(for: choice)
    }

    @MainActor
    static func iconImage(for choice: AppThemeChoice) -> NSImage? {
        let wantsDark: Bool
        switch choice {
        case .paperDark:
            wantsDark = true
        case .paperLight:
            wantsDark = false
        case .system:
            wantsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let name = wantsDark ? "OwnwardIconDark" : "OwnwardIconLight"
        guard let url = resourceURL(name: name, extension: "png", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func resourceURL(name: String, extension fileExtension: String, subdirectory: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
    }
}

struct OwnwardWordmark: View {
    @Environment(\.ownwardTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            if let icon = OwnwardBrand.iconImage(for: theme.choice) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            Text("Ownward")
                .font(.custom(OwnwardBrand.wordmarkFontName, fixedSize: 17))
                .foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ownward")
    }
}
