import XCTest
@testable import OverlayStudio

@MainActor
final class LocalizationTests: XCTestCase {
    private func makeStore(defaults: UserDefaults, systemPreferredLanguages: [String]? = nil) -> LocalizationStore {
        LocalizationStore(defaults: defaults, systemPreferredLanguages: systemPreferredLanguages, appDomains: [])
    }

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

        let store = makeStore(defaults: defaults)
        XCTAssertEqual(store.selection, .system)

        store.selection = .japanese

        let reloaded = makeStore(defaults: defaults)
        XCTAssertEqual(reloaded.selection, .japanese)
        XCTAssertEqual(reloaded.resolvedLanguage, .japanese)
    }

    func testLanguageSelectionUpdatesProcessAppleLanguages() {
        let suiteName = "run.libo.overlay-studio.localization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = makeStore(defaults: defaults, systemPreferredLanguages: ["en-US"])
        store.selection = .simplifiedChinese

        let argumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        XCTAssertEqual(
            argumentDomain["AppleLanguages"] as? [String],
            ["zh-Hans-CN", "zh-Hans", "zh_CN", "zh"]
        )
        XCTAssertEqual(
            defaults.array(forKey: "AppleLanguages") as? [String],
            ["zh-Hans-CN", "zh-Hans", "zh_CN", "zh"]
        )
    }

    func testStoredLanguageCanBeAppliedBeforeStoreCreation() {
        let suiteName = "run.libo.overlay-studio.localization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguageSelection.simplifiedChinese.rawValue, forKey: AppLocalizer.selectionDefaultsKey)
        AppLocalizer.applyStoredProcessLanguagePreference(defaults: defaults, preferredLanguages: ["en-US"])

        let argumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        XCTAssertEqual(
            argumentDomain["AppleLanguages"] as? [String],
            ["zh-Hans-CN", "zh-Hans", "zh_CN", "zh"]
        )
    }

    func testSystemLanguageSelectionUsesLaunchPreferredLanguagesForAppKit() {
        let suiteName = "run.libo.overlay-studio.localization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = makeStore(defaults: defaults, systemPreferredLanguages: ["zh-Hant-TW"])
        store.selection = .japanese
        store.selection = .system

        let argumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        XCTAssertNil(argumentDomain["AppleLanguages"])
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(store.resolvedLanguage, .traditionalChinese)
    }

    func testSystemLanguageSelectionClearsStaleProcessAppleLanguages() {
        let suiteName = "run.libo.overlay-studio.localization-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["en"], forKey: "AppleLanguages")
        defaults.setVolatileDomain(["AppleLanguages": ["en"]], forName: UserDefaults.argumentDomain)

        let store = makeStore(defaults: defaults, systemPreferredLanguages: ["zh-Hans-CN"])

        XCTAssertEqual(store.selection, .system)
        XCTAssertEqual(store.resolvedLanguage, .simplifiedChinese)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertNil(defaults.volatileDomain(forName: UserDefaults.argumentDomain)["AppleLanguages"])
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

    func testLanguageMenuTitleIsLocalized() {
        XCTAssertEqual(
            AppLocalizer.string("menu.language", language: .simplifiedChinese),
            "语言"
        )
        XCTAssertEqual(
            AppLocalizer.string("menu.language", language: .english),
            "Language"
        )
    }

    func testActivityAndExportLabelsAvoidLegacyFITOnlyWording() {
        XCTAssertEqual(
            AppLocalizer.string("menu.openFit", language: .simplifiedChinese),
            "打开运动文件..."
        )
        XCTAssertEqual(
            AppLocalizer.string("sidebar.source.subtitle", language: .english),
            "Video and activity data"
        )
        XCTAssertEqual(
            AppLocalizer.string("exportMode.video", language: .traditionalChinese),
            "合成影片"
        )
        XCTAssertEqual(AppLocalizer.string("timecode.milliseconds", language: .japanese), "ミリ秒")
    }

    func testAppearanceSelectionMapsToColorScheme() {
        XCTAssertNil(AppAppearanceSelection.system.colorScheme)
        XCTAssertEqual(AppAppearanceSelection.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceSelection.dark.colorScheme, .dark)
        XCTAssertEqual(AppAppearanceSelection.selection(from: "unknown"), .system)
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
            "DataLayer Studio プリセットファイルまたは旧形式の JSON プリセットファイルを選択します。"
        )
    }
}
