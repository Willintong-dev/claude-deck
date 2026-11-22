import Foundation
import Testing
@testable import DeckCore

struct AppearanceTests {
    let directory = TemporaryDirectory()

    @Test func everyThemeHasAValidFullPalette() {
        #expect(Set(TerminalTheme.all.map(\.id)).count == TerminalTheme.all.count)
        for theme in TerminalTheme.all {
            #expect(theme.ansi.count == 16, "\(theme.id)")
            for hex in theme.ansi + [theme.background, theme.foreground, theme.cursor, theme.selection] {
                #expect(RGB(hex: hex) != nil, "\(theme.id) \(hex)")
            }
        }
        #expect(TerminalTheme.named("deck-dark").isDark)
        #expect(!TerminalTheme.named("solarized-light").isDark)
        #expect(TerminalTheme.named("no-existe") == TerminalTheme.fallback)
    }

    @Test func parsesHexColors() {
        #expect(RGB(hex: "#FF8000") == RGB(hex: "ff8000"))
        #expect(RGB(hex: "FF8000")?.green == 0x80)
        #expect(RGB(hex: "FFF") == nil)
        #expect(RGB(hex: "GG0000") == nil)
    }

    @Test func sessionsInheritDefaultsUntilTheyOverrideSomething() {
        var settings = AppearanceSettings()
        #expect(settings.resolved(for: "s1") == .standard)

        settings.update("s1", scope: .session) { $0.themeId = "nord" }
        settings.update(nil, scope: .all) { $0.fontSize = 14 }

        #expect(settings.resolved(for: "s1").themeId == "nord")
        #expect(settings.resolved(for: "s1").fontSize == 14)
        #expect(settings.resolved(for: "s2").themeId == "deck-dark")
        #expect(settings.isCustomized("s1"))
        #expect(!settings.isCustomized("s2"))
    }

    @Test func choosingTheDefaultValueDropsTheOverride() {
        var settings = AppearanceSettings()
        settings.update("s1", scope: .session) { $0.themeId = "nord" }
        settings.update("s1", scope: .session) { $0.themeId = "deck-dark" }
        #expect(!settings.isCustomized("s1"))
    }

    @Test func applyingToAllSessionsOverridesWhatEachOneCustomizedInThatField() {
        var settings = AppearanceSettings()
        settings.update("s1", scope: .session) { $0.themeId = "nord" }
        settings.update("s1", scope: .session) { $0.fontSize = 16 }
        settings.update("s2", scope: .session) { $0.themeId = "dracula" }

        settings.update("s2", scope: .all) { $0.themeId = "deck-dark" }

        #expect(settings.resolved(for: "s1").themeId == "deck-dark")
        #expect(settings.resolved(for: "s2").themeId == "deck-dark")
        #expect(settings.resolved(for: "s3").themeId == "deck-dark")
        #expect(settings.resolved(for: "s1").fontSize == 16)
        #expect(!settings.isCustomized("s2"))

        settings.zoom("s1", steps: 2, scope: .all)
        #expect(settings.resolved(for: "s1").fontSize == 18)
        #expect(settings.resolved(for: "s3").fontSize == 18)
        #expect(!settings.isCustomized("s1"))
    }

    @Test func applyingToAllOnlyTouchesTheFieldThatChanged() {
        var settings = AppearanceSettings()
        settings.update("s1", scope: .session) { $0.fontName = "Menlo" }

        settings.update("s2", scope: .all) { $0.themeId = "nord" }

        #expect(settings.resolved(for: "s1").fontName == "Menlo")
        #expect(settings.resolved(for: "s1").themeId == "nord")
        #expect(settings.resolved(for: "s2").fontName == TerminalAppearance.systemFont)
    }

    @Test func changingDefaultsKeepsWhatEachSessionCustomized() {
        var settings = AppearanceSettings()
        settings.update("s1", scope: .session) { $0.fontName = "Menlo" }
        settings.update(nil, scope: .all) { $0.fontName = "Menlo" }

        #expect(settings.resolved(for: "s1").fontName == "Menlo")
        #expect(!settings.isCustomized("s1"))

        settings.update("s2", scope: .session) { $0.fontName = TerminalAppearance.systemFont }
        settings.update(nil, scope: .all) { $0.themeId = "dracula" }
        #expect(settings.resolved(for: "s2").fontName == TerminalAppearance.systemFont)
        #expect(settings.resolved(for: "s2").themeId == "dracula")
    }

    @Test func zoomStaysWithinLimitsAndResets() {
        var settings = AppearanceSettings()
        settings.zoom("s1", steps: 3)
        #expect(settings.resolved(for: "s1").fontSize == 15.5)

        settings.zoom("s1", steps: 100)
        #expect(settings.resolved(for: "s1").fontSize == TerminalAppearance.sizeRange.upperBound)
        settings.zoom("s1", steps: -100)
        #expect(settings.resolved(for: "s1").fontSize == TerminalAppearance.sizeRange.lowerBound)

        settings.update("s1", scope: .session) { $0.themeId = "nord" }
        settings.resetZoom("s1")
        #expect(settings.resolved(for: "s1").fontSize == 12.5)
        #expect(settings.resolved(for: "s1").themeId == "nord")

        settings.reset("s1")
        #expect(!settings.isCustomized("s1"))
    }

    @Test func resettingZoomForAllReturnsEverySessionToTheStandardSize() {
        var settings = AppearanceSettings()
        settings.zoom("s1", steps: 4, scope: .all)
        settings.zoom("s2", steps: 2)
        settings.update("s2", scope: .session) { $0.themeId = "nord" }

        settings.resetZoom("s1", scope: .all)

        #expect(settings.resolved(for: "s1").fontSize == TerminalAppearance.standard.fontSize)
        #expect(settings.resolved(for: "s2").fontSize == TerminalAppearance.standard.fontSize)
        #expect(settings.resolved(for: "s2").themeId == "nord")
    }

    @Test func storeRoundTripsAndFallsBackOnBadFiles() throws {
        let store = AppearanceStore(file: directory.url.appendingPathComponent("deck/appearance.json"))
        #expect(store.load() == AppearanceSettings())

        var settings = AppearanceSettings()
        settings.appTheme = .dark
        settings.update(nil, scope: .all) { $0.fontSize = 13 }
        settings.update("s1", scope: .session) { $0.themeId = "gruvbox-dark" }
        try store.save(settings)
        #expect(store.load() == settings)

        write(#"{"appTheme":"raro","overrides":{"s1":{"fontSize":20}}}"#, to: store.file)
        #expect(store.load().appTheme == .system)
        #expect(store.load().resolved(for: "s1").fontSize == 20)
    }
}
