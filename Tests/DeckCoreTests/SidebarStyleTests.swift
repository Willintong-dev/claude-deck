import Foundation
import Testing
@testable import DeckCore

struct SidebarStyleTests {
    let directory = TemporaryDirectory()

    @Test func detailLineFollowsAFixedOrderAndSkipsEmptyValues() {
        var style = SidebarStyle()
        let values: [SidebarDetail: String] = [
            .preview: "hola\nmundo",
            .lastActivity: "hace 2 min",
            .branch: "",
            .folder: "pagos",
            .context: "87k ctx",
        ]
        #expect(style.detailLine(values) == "pagos · 87k ctx · hace 2 min")

        style.show(.branch, false)
        style.show(.context, false)
        style.show(.preview, true)
        #expect(style.detailLine(values) == "pagos · hace 2 min · hola mundo")

        for detail in SidebarDetail.allCases { style.show(detail, false) }
        #expect(style.detailLine(values).isEmpty)
    }

    @Test func avatarsHaveStableColorsAndReadableInitials() {
        let id = "8e1f7c2a-1b2c-4d5e-8f90-123456789abc"
        #expect(SessionAvatar.colorHex(for: id) == SessionAvatar.colorHex(for: id))
        #expect(SessionAvatar.palette.allSatisfy { RGB(hex: $0) != nil })
        let colors = Set((0..<40).map { SessionAvatar.colorHex(for: "sesion-\($0)") })
        #expect(colors.count > 6)

        #expect(SessionAvatar.initials(of: "Gestor nativo de sesiones") == "GN")
        #expect(SessionAvatar.initials(of: "Caio") == "C")
        #expect(SessionAvatar.initials(of: "transaction-rails") == "TR")
        #expect(SessionAvatar.initials(of: "  ¿qué pasó?  ") == "QP")
        #expect(SessionAvatar.initials(of: "") == "?")
    }

    @Test func sizesStayWithinTheirRanges() {
        var style = SidebarStyle()
        style.setTitleSize(100)
        style.setDetailSize(1)
        #expect(style.titleSize == SidebarStyle.titleSizeRange.upperBound)
        #expect(style.detailSize == SidebarStyle.detailSizeRange.lowerBound)
    }

    @Test func everyAccentHasAValidColorExceptTheSystemOne() {
        #expect(SidebarAccent.system.hex == nil)
        for accent in SidebarAccent.allCases where accent != .system {
            #expect(accent.hex.flatMap(RGB.init(hex:)) != nil, "\(accent)")
        }
    }

    @Test func backgroundUsesAKnownThemeOrNone() {
        var style = SidebarStyle()
        #expect(style.backgroundTheme == nil)
        style.backgroundThemeId = "nord"
        #expect(style.backgroundTheme?.name == "Nord")
        style.backgroundThemeId = "no-existe"
        #expect(style.backgroundTheme == nil)
    }

    @Test func savesInsideAppearanceAndToleratesOldOrBadFiles() throws {
        let store = AppearanceStore(file: directory.url.appendingPathComponent("deck/appearance.json"))
        var settings = AppearanceSettings()
        settings.sidebar.fontFamily = "Avenir Next"
        settings.sidebar.setTitleSize(15)
        settings.sidebar.show(.branch, false)
        settings.sidebar.density = .compact
        settings.sidebar.accent = .purple
        settings.sidebar.statusColors = .monochrome
        settings.sidebar.backgroundThemeId = "dracula"
        settings.sidebar.iconStyle = .simple
        try store.save(settings)
        #expect(store.load().sidebar == settings.sidebar)

        write(#"{"appTheme":"dark"}"#, to: store.file)
        #expect(store.load().sidebar == SidebarStyle())

        write(#"{"sidebar":{"titleSize":99,"density":"rara","details":["folder","nada"]}}"#, to: store.file)
        let loaded = store.load().sidebar
        #expect(loaded.titleSize == SidebarStyle.titleSizeRange.upperBound)
        #expect(loaded.density == .normal)
        #expect(loaded.details == SidebarStyle().details)
        #expect(loaded.iconStyle == .avatar)
    }
}
