import Testing
@testable import OwnwardCore

@Suite("App preferences")
struct AppPreferencesTests {
    @Test("zoom uses bounded ten-percent steps")
    func zoomBounds() {
        #expect(ZoomLevel.increased(from: 1.0) == 1.1)
        #expect(ZoomLevel.decreased(from: 1.0) == 0.9)
        #expect(ZoomLevel.increased(from: ZoomLevel.maximum) == ZoomLevel.maximum)
        #expect(ZoomLevel.decreased(from: ZoomLevel.minimum) == ZoomLevel.minimum)
    }

    @Test("three appearance choices remain stable")
    func themeChoices() {
        #expect(AppThemeChoice.allCases == [.system, .paperLight, .paperDark])
        #expect(AppThemeChoice.system.usesSystemAppearance)
        #expect(AppThemeChoice.system.fontFamily == .system)
        #expect(AppThemeChoice.system.surfaceHex == nil)
        #expect(AppThemeChoice.paperLight.fontFamily == .ubuntu)
        #expect(AppThemeChoice.paperLight.surfaceHex == 0xF0EAD8)
        #expect(AppThemeChoice.paperLight.inkHex == 0x1D1D1B)
        #expect(AppThemeChoice.paperDark.fontFamily == .ubuntu)
        #expect(AppThemeChoice.paperDark.surfaceHex == 0x1D1D1B)
        #expect(AppThemeChoice.paperDark.inkHex == 0xF0EAD8)
    }

    @Test("table task column width stays usable and resettable")
    func tableColumnWidth() {
        #expect(TableTaskColumnWidth.defaultValue == 260)
        #expect(TableTaskColumnWidth.clamped(90) == TableTaskColumnWidth.minimum)
        #expect(TableTaskColumnWidth.clamped(900) == TableTaskColumnWidth.maximum)
        #expect(TableTaskColumnWidth.clamped(340) == 340)
    }

    @Test("default windows fit the visible display and retain vertical resize room")
    func adaptiveWindowSize() {
        let laptop = WindowSizePolicy.defaultSize(in: WindowDimensions(width: 1170, height: 732))
        let external = WindowSizePolicy.defaultSize(in: WindowDimensions(width: 2560, height: 1400))

        #expect(WindowSizePolicy.minimum == WindowDimensions(width: 760, height: 500))
        #expect(laptop.width < 1170)
        #expect(laptop.height < 732)
        #expect(external == WindowDimensions(width: 1240, height: 800))
        #expect(WindowSizePolicy.shouldClampLegacyWindow(WindowDimensions(width: 1488, height: 960)))
        #expect(!WindowSizePolicy.shouldClampLegacyWindow(WindowDimensions(width: 1000, height: 650)))
    }
}
