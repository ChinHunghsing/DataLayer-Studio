import XCTest
@testable import OverlayStudio

@MainActor
final class LocalizationTests: XCTestCase {
    func testPreferredLanguageResolutionSupportsRequestedLanguages() {
        XCTAssertEqual(
            AppLocalizer.resolvedLanguage(forPreferredLanguages: ["zh-Hans-CN"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLocalizer.resolvedLanguage(forPreferredLanguages: ["zh-Hant-TW"]),
            .traditionalChinese
        )
        XCTAssertEqual(
            AppLocalizer.resolvedLanguage(forPreferredLanguages: ["en-US"]),
            .english
        )
        XCTAssertEqual(
            AppLocalizer.resolvedLanguage(forPreferredLanguages: ["ja-JP"]),
            .japanese
        )
    }

    func testTranslationTablesCoverAllEnglishKeys() {
        for language in AppResolvedLanguage.allCases {
            XCTAssertEqual(AppLocalizer.missingTranslationKeys(for: language), [], "\(language.rawValue) has missing localization keys")
        }
    }

    func testManualLanguageSelectionPersists() {
        let suiteName = "run.libo.overlay-studio.localization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalizationStore(defaults: defaults)
        XCTAssertEqual(store.selection, .system)

        store.selection = .japanese

        let reloaded = LocalizationStore(defaults: defaults)
        XCTAssertEqual(reloaded.selection, .japanese)
        XCTAssertEqual(reloaded.resolvedLanguage, .japanese)
    }

    func testStoredSelectionFallsBackToLegacyAppDomain() {
        let suiteName = "run.libo.datalayer-studio.localization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyDomain = "\(suiteName).legacy"
        defaults.setPersistentDomain(
            [AppLocalizer.selectionDefaultsKey: AppLanguageSelection.traditionalChinese.rawValue],
            forName: legacyDomain
        )
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
        }

        XCTAssertEqual(
            AppLocalizer.storedSelection(defaults: defaults, appDomains: [legacyDomain]),
            .traditionalChinese
        )
    }

    func testLocalizedStringsUseRequestedLanguage() {
        XCTAssertEqual(
            AppLocalizer.string("toolbar.sportStart", language: .simplifiedChinese),
            "运动开始"
        )
        XCTAssertEqual(
            AppLocalizer.string("toolbar.sportStart", language: .traditionalChinese),
            "運動開始"
        )
        XCTAssertEqual(
            AppLocalizer.string("toolbar.sportStart", language: .english),
            "Sport Start"
        )
        XCTAssertEqual(
            AppLocalizer.string("toolbar.sportStart", language: .japanese),
            "運動開始"
        )
    }

    func testExportResolutionPresetTitlesAreLocalized() {
        XCTAssertEqual(
            AppLocalizer.string("resolutionPreset.vertical-1080", language: .simplifiedChinese),
            "竖屏 1080×1920"
        )
        XCTAssertEqual(
            AppLocalizer.string("resolutionPreset.vertical-1080", language: .english),
            "Vertical 1080×1920"
        )
    }

    func testFilePanelActionsAreLocalized() {
        XCTAssertEqual(
            AppLocalizer.string("panel.open", language: .simplifiedChinese),
            "打开"
        )
        XCTAssertEqual(
            AppLocalizer.string("panel.export", language: .english),
            "Export"
        )
    }

    func testFilePanelMessagesAreLocalized() {
        XCTAssertEqual(
            AppLocalizer.string("panel.chooseSourceVideo.message", language: .simplifiedChinese),
            "选择要放在透明浮层下方的源视频。"
        )
        XCTAssertEqual(
            AppLocalizer.string("panel.importLayoutPresets.message", language: .japanese),
            "DataLayer Studio から書き出した配置プリセット JSON ファイルを選択します。"
        )
    }
}
