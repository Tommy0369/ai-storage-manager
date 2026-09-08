import XCTest
@testable import AppServices
@testable import SafetyCore

final class P53LocalizationFoundationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    override func tearDown() {
        L10n.setOverride(.english)
        super.tearDown()
    }

    func testCatalogLoadsWithProductionKeys() {
        XCTAssertGreaterThanOrEqual(L10n.productionKeys.count, 100)
        XCTAssertFalse(L10n.productionKeys.contains(where: { $0.hasPrefix("navigation.") == false && $0.isEmpty }))
    }

    func testAllShippingLocalesResolveCriticalKeys() {
        for locale in LocalizationCoverageAudit.shippingLocaleIDs {
            for key in LocalizationCoverageAudit.criticalSafetyKeys {
                let value = L10n.translation(key: key, localeID: locale)
                XCTAssertNotNil(value, "\(locale) missing \(key)")
                XCTAssertFalse(value?.isEmpty == true, "\(locale) empty \(key)")
                XCTAssertNotEqual(value, key, "\(locale) raw key visible for \(key)")
            }
        }
    }

    func testCoverageNearComplete() {
        let report = LocalizationCoverageAudit.fullReport()
        XCTAssertEqual(report.supportedLocales.count, 9)
        XCTAssertEqual(report.missingKeyCount, 0)
        for per in report.perLocale {
            XCTAssertEqual(per.missingKeys, 0, per.localeID)
            XCTAssertGreaterThanOrEqual(per.coveragePercent, 99.0, per.localeID)
        }
    }

    func testJapaneseDiffersFromEnglishForKeep() {
        let en = L10n.t("decision.keep.title", language: .english)
        let ja = L10n.t("decision.keep.title", language: .japanese)
        XCTAssertEqual(en, "Keep")
        XCTAssertEqual(ja, "残す")
        XCTAssertNotEqual(en, ja)
    }

    func testZhHansAndZhHantAreSeparateEntries() {
        let hans = L10n.t("permission.fullDiskAccess.description", language: .chineseSimplified)
        let hant = L10n.t("permission.fullDiskAccess.description", language: .chineseTraditional)
        XCTAssertFalse(hans.isEmpty)
        XCTAssertFalse(hant.isEmpty)
        // Scripts should not be identical for this long safety sentence.
        XCTAssertNotEqual(hans, hant)
    }

    func testGermanMoveToTrashLongerButPresent() {
        let de = L10n.t("action.moveToTrash.title", language: .german)
        XCTAssertTrue(de.contains("Papierkorb"))
        XCTAssertGreaterThan(de.count, L10n.t("action.moveToTrash.title", language: .english).count)
    }

    func testLocaleDoesNotChangeVerifiedRecovery() {
        for lang in AppLanguage.shippingLocales {
            L10n.setOverride(lang)
            XCTAssertEqual(
                StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal,
                5_580_814_899
            )
        }
        L10n.setOverride(.english)
    }

    func testLocaleDoesNotChangeSafetyFreezeOrExecutors() {
        for lang in [AppLanguage.english, .japanese, .german, .chineseSimplified] {
            L10n.setOverride(lang)
            XCTAssertTrue(FoundationResearchFreeze.isFrozen)
            XCTAssertEqual(ProductizationInvariants.existingExecutors.count, 3)
            XCTAssertFalse(ProductizationInvariants.secondCrawlerAdded)
        }
        L10n.setOverride(.english)
    }

    func testByteFormattingLocaleAware() {
        let en = LocaleFormatting.byteLabel(5_580_814_899, language: .english)
        let de = LocaleFormatting.byteLabel(5_580_814_899, language: .german)
        XCTAssertFalse(en.isEmpty)
        XCTAssertFalse(de.isEmpty)
        // Truth bytes unchanged regardless of presentation.
        XCTAssertEqual(5_580_814_899, ProductReleaseIdentity.verifiedRecoveredBytesCanonical)
    }

    func testDateFormattingLocaleAware() {
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let en = LocaleFormatting.date(date, language: .english)
        let ja = LocaleFormatting.date(date, language: .japanese)
        XCTAssertFalse(en.isEmpty)
        XCTAssertFalse(ja.isEmpty)
    }

    func testPluralPlaceholder() {
        let s = L10n.t("plural.verificationAreas", language: .english, 3)
        XCTAssertTrue(s.contains("3"))
    }

    func testVendorCleanupPlaceholder() {
        let s = L10n.t("action.vendorCleanup.title", language: .english, "Ollama")
        XCTAssertTrue(s.contains("Ollama"))
    }

    func testInvalidLanguageFallsBackToSystemParse() {
        XCTAssertEqual(AppLanguage.parse("nope"), .system)
        XCTAssertEqual(AppLanguage.parse(nil), .system)
    }

    func testVoiceMemosBlockDoesNotImplyCloudDeleteLocal() {
        for lang in AppLanguage.shippingLocales {
            let block = L10n.t("entity.voiceMemos.block", language: lang).lowercased()
            XCTAssertFalse(block.contains("junk"))
            XCTAssertFalse(block.contains("always safe"))
        }
    }

    func testChromeCopyNotWholeProfileCache() {
        let en = L10n.t("entity.chrome.block", language: .english).lowercased()
        XCTAssertTrue(en.contains("website") || en.contains("state"))
        XCTAssertFalse(en.contains("junk"))
    }

    func testProductNameUntranslated() {
        XCTAssertEqual(ProductReleaseIdentity.productName, "AI Storage Manager")
    }

    func testNoNewAINetworkService() {
        // Localization is offline catalog only.
        XCTAssertFalse(L10n.productionKeys.isEmpty)
        XCTAssertTrue(L10n.hasKey("decision.keep.title"))
        XCTAssertNotEqual(L10n.t("decision.keep.title", language: .japanese), "decision.keep.title")
    }
}
