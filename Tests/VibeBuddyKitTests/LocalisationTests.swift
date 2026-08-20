import Testing
import Foundation
@testable import VibeBuddyKit

@Suite("Language resolution")
struct AppLanguageTests {

    // `.system` stays a distinct case rather than being resolved once at
    // launch: someone who changes their macOS language expects the app to
    // follow, and a stored resolved value would freeze it forever.
    @Test("system follows macOS", arguments: [
        (["fr-FR", "en-US"], AppLanguage.french),
        (["fr"],             .french),
        (["en-GB"],          .english),
        (["de-DE"],          .english),
        ([],                 .english),
    ])
    func systemFollowsOS(_ preferred: [String], _ expected: AppLanguage) {
        #expect(AppLanguage.system.resolved(preferred: preferred) == expected)
    }

    // A language we do not have falls back whole rather than part-way: a
    // Portuguese user gets English, not half a French interface.
    @Test("an unsupported language falls back to English, not to a partial match")
    func unsupportedFallsBack() {
        #expect(AppLanguage.system.resolved(preferred: ["pt-BR"]) == .english)
    }

    @Test("an explicit choice ignores the system")
    func explicitWins() {
        #expect(AppLanguage.french.resolved(preferred: ["en-US"]) == .french)
        #expect(AppLanguage.english.resolved(preferred: ["fr-FR"]) == .english)
    }

    @Test("each language names itself in its own language")
    func selfNaming() {
        #expect(AppLanguage.french.displayName == "Français")
        #expect(AppLanguage.english.displayName == "English")
    }

    // Dates follow the interface, so a French panel never prints "August 23"
    // under "semaine".
    @Test("the locale follows the resolved language")
    func localeFollows() {
        #expect(AppLanguage.french.locale.identifier == "fr_FR")
        #expect(AppLanguage.english.locale.identifier == "en_US")
    }
}

@Suite("String catalogue")
struct StringsTests {

    @Test("both catalogues answer for the same keys")
    func bothLanguagesComplete() {
        // The type system already guarantees this — a missing string would not
        // compile. This asserts the values are actually filled in rather than
        // left as empty placeholders.
        for strings in [Strings.french, Strings.english] {
            #expect(!strings.noSessions.isEmpty)
            #expect(!strings.sessionsTitle.isEmpty)
            #expect(!strings.usageTitle.isEmpty)
            #expect(!strings.quit.isEmpty)
            #expect(!strings.alertFinished.isEmpty)
            #expect(!strings.emptyHint.isEmpty)
        }
    }

    @Test("interpolated strings place their value")
    func interpolation() {
        #expect(Strings.french.sessionsWorking(3).contains("3"))
        #expect(Strings.english.sessionsWorking(3).contains("3"))
        #expect(Strings.french.noMatch("notch").contains("notch"))
        #expect(Strings.english.contextTooltip(1000, 200_000).contains("200000"))
    }

    @Test("the two languages actually differ")
    func notCopyPasted() {
        #expect(Strings.french.noSessions != Strings.english.noSessions)
        #expect(Strings.french.emptyHint != Strings.english.emptyHint)
        #expect(Strings.french.alertFinished != Strings.english.alertFinished)
    }

    @Test("lookup routes to the right catalogue")
    func routing() {
        #expect(Strings.for(.french).usageTitle == "CONSOMMATION")
        #expect(Strings.for(.english).usageTitle == "USAGE")
    }

    // Regression guard: `ToolActionClassifier` used to return French words straight
    // into the row, so an English panel showed "édition · SessionStore.swift". If a
    // label ever leaks back out of the Kit, both catalogues render it identically.
    @Test("a tool label is translated, not passed through", arguments: [
        ToolLabel.shell, .editing, .writing, .reading,
        .searching, .listing, .webSearch, .delegating, .planning,
    ])
    func toolLabelsDiffer(_ tool: ToolLabel) {
        let fr = Strings.french.label(for: tool)
        let en = Strings.english.label(for: tool)
        #expect(!fr.isEmpty)
        #expect(!en.isEmpty)
        #expect(fr != en)
    }

    // The one label that must NOT be translated: an unknown tool is named, not described.
    @Test("an unknown tool keeps its own name in both languages")
    func unknownToolPassesThrough() {
        #expect(Strings.french.label(for: .other("mcp__weird")) == "mcp__weird")
        #expect(Strings.english.label(for: .other("mcp__weird")) == "mcp__weird")
    }

    @Test("every tool label is filled in", arguments: [
        ToolLabel.shell, .editing, .writing, .reading, .searching, .listing,
        .web, .webSearch, .delegating, .planning, .notebook, .question,
    ])
    func everyToolLabelFilled(_ tool: ToolLabel) {
        #expect(!Strings.french.label(for: tool).isEmpty)
        #expect(!Strings.english.label(for: tool).isEmpty)
    }
}

@Suite("Localisation store")
@MainActor
struct LocalisationStoreTests {

    private func store() -> (Localisation, UserDefaults) {
        let suite = UserDefaults(suiteName: "vibebuddy.tests.\(UUID().uuidString)")!
        return (Localisation(defaults: suite), suite)
    }

    // First launch stores nothing, so `.system` applies — detection is not a
    // separate step, it is what `.system` means.
    @Test("a fresh install starts on system")
    func freshInstallFollowsSystem() {
        let (l10n, _) = store()
        #expect(l10n.language == .system)
    }

    @Test("a choice persists")
    func choicePersists() {
        let (l10n, defaults) = store()
        l10n.set(.english)
        #expect(defaults.string(forKey: Localisation.storageKey) == "en")
        let reopened = Localisation(defaults: defaults)
        #expect(reopened.language == .english)
        #expect(reopened.strings.usageTitle == "USAGE")
    }

    @Test("setting the same language changes nothing")
    func idempotent() {
        let (l10n, _) = store()
        let before = l10n.strings.usageTitle
        l10n.set(l10n.language)
        #expect(l10n.strings.usageTitle == before)
    }

    @Test("strings follow the language immediately")
    func stringsFollow() {
        let (l10n, _) = store()
        l10n.set(.french)
        #expect(l10n.strings.usageTitle == "CONSOMMATION")
        l10n.set(.english)
        #expect(l10n.strings.usageTitle == "USAGE")
    }
}
