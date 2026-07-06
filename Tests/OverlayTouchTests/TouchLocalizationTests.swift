import XCTest
@testable import OverlayTouch

final class TouchLocalizationTests: XCTestCase {
    func testAllLanguagesShareTheSameKeySet() {
        guard let englishKeys = TouchLocalizer.tables["en"].map({ Set($0.keys) }) else {
            XCTFail("Missing English table")
            return
        }

        for language in ["zh-Hans", "zh-Hant", "ja"] {
            guard let keys = TouchLocalizer.tables[language].map({ Set($0.keys) }) else {
                XCTFail("Missing table for \(language)")
                continue
            }
            XCTAssertEqual(
                keys, englishKeys,
                "Localization keys mismatch for \(language): missing \(englishKeys.subtracting(keys).sorted()), extra \(keys.subtracting(englishKeys).sorted())"
            )
        }
    }

    func testLanguageResolution() {
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "zh_CN")), .simplifiedChinese)
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "zh-Hans-CN")), .simplifiedChinese)
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "zh_TW")), .traditionalChinese)
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "zh-Hant-HK")), .traditionalChinese)
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "ja_JP")), .japanese)
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "en_US")), .english)
        XCTAssertEqual(TouchLanguage.resolved(from: Locale(identifier: "fr_FR")), .english)
    }

    func testMessageFormattingReplacesPlaceholdersInOrder() {
        let localizer = TouchLocalizer(language: .english)
        let formatted = localizer.format(TouchMessage("status.loadedVideo", ["ride.mov"]))
        XCTAssertEqual(formatted, "Loaded video ride.mov.")
    }

    func testUnknownKeyFallsBackToKeyItself() {
        let localizer = TouchLocalizer(language: .japanese)
        XCTAssertEqual(localizer.string("nonexistent.key"), "nonexistent.key")
    }

    func testComponentLocalizationCoversAllKinds() {
        for language in ["en", "zh-Hans", "zh-Hant", "ja"] {
            let localizer = TouchLocalizer(language: TouchLanguage(rawValue: language)!)
            for kind in OverlayComponentID.allCases {
                let value = localizer.string(kind.localizationKey)
                XCTAssertNotEqual(value, kind.localizationKey, "Missing \(language) name for \(kind)")
            }
        }
    }
}

import OverlayCore
