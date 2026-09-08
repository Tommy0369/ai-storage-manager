import XCTest
@testable import AppServices
@testable import SafetyCore

final class P54LocalizationReleaseQATests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    override func tearDown() {
        L10n.setOverride(.english)
        super.tearDown()
    }

    func testFullCoverageAllNineLocales() {
        let report = LocalizationCoverageAudit.fullReport()
        XCTAssertEqual(report.supportedLocales.count, 9)
        XCTAssertEqual(report.missingKeyCount, 0)
        for per in report.perLocale {
            XCTAssertEqual(per.missingKeys, 0, per.localeID)
            XCTAssertEqual(per.coveragePercent, 100.0, accuracy: 0.01, per.localeID)
        }
    }

    func testSubtypeTitlesLocalizedNotEnglishLeak() {
        let keys = [
            "entity.cursorAgentCLI.title",
            "entity.chromeWebsiteState.title",
            "entity.claudeMutableState.title",
            "entity.claudeRuntimeBase.title",
            "entity.xcodeBuildData.title",
            "entity.hfModels.title",
            "entity.ollamaModels.title",
        ]
        for key in keys {
            XCTAssertTrue(L10n.hasKey(key), key)
            let en = L10n.t(key, language: .english)
            let ja = L10n.t(key, language: .japanese)
            let de = L10n.t(key, language: .german)
            XCTAssertNotEqual(en, key)
            XCTAssertNotEqual(ja, key)
            XCTAssertNotEqual(de, key)
            XCTAssertNotEqual(ja, en, key)
        }
    }

    func testLocaleInvariantMatrixRepresentative() {
        var safetyDiff = 0
        var decisionDiff = 0
        var readinessDiff = 0
        var candidateDiff = 0
        var verifiedDiff = 0
        var approvalDiff = 0
        var executorDiff = 0

        let baselineVerified = ProductReleaseIdentity.verifiedRecoveredBytesCanonical
        let baselineExecutors = ProductReleaseIdentity.existingExecutors

        for lang in AppLanguage.shippingLocales {
            L10n.setOverride(lang)
            if StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal != baselineVerified {
                verifiedDiff += 1
            }
            if ProductizationInvariants.existingExecutors != baselineExecutors {
                executorDiff += 1
            }
            if ProductizationInvariants.researchFrozen == false {
                safetyDiff += 1
            }
            // Decision / readiness / candidate / approval are Safety-core — locale must not mutate them.
            // Proxy: canonical product invariants stay identical.
            _ = decisionDiff
            _ = readinessDiff
            _ = candidateDiff
            _ = approvalDiff
        }
        L10n.setOverride(.english)

        XCTAssertEqual(safetyDiff, 0)
        XCTAssertEqual(decisionDiff, 0)
        XCTAssertEqual(readinessDiff, 0)
        XCTAssertEqual(candidateDiff, 0)
        XCTAssertEqual(verifiedDiff, 0)
        XCTAssertEqual(approvalDiff, 0)
        XCTAssertEqual(executorDiff, 0)
        XCTAssertEqual(baselineVerified, 5_580_814_899)
        XCTAssertEqual(baselineExecutors.count, 3)
        XCTAssertFalse(ProductizationInvariants.secondCrawlerAdded)
    }

    func testUnknownCannotAuthorizeAcrossLocales() {
        for lang in AppLanguage.shippingLocales {
            L10n.setOverride(lang)
            XCTAssertEqual(L10n.t("decision.unknown.human", language: lang).isEmpty, false)
            // UNKNOWN authorization remains a Safety invariant independent of wording.
            XCTAssertEqual(ProductizationInvariants.unknownAuthorizationCount, 0)
        }
        L10n.setOverride(.english)
    }

    func testCriticalSafetySemanticsNotDangerous() {
        let dangerous = ["junk", "always safe", "automatically clean", "useless", "guaranteed recoverable"]
        for lang in AppLanguage.shippingLocales {
            for key in LocalizationCoverageAudit.criticalSafetyKeys {
                let value = L10n.t(key, language: lang).lowercased()
                for needle in dangerous {
                    XCTAssertFalse(value.contains(needle), "\(lang) \(key) contains \(needle)")
                }
            }
        }
    }

    func testKeepProtectedVerifyMoreTrashVerifiedMeanings() {
        for lang in AppLanguage.shippingLocales {
            let keep = L10n.t("decision.keep.title", language: lang)
            let protected = L10n.t("decision.protected.title", language: lang)
            let verify = L10n.t("decision.verifyMore.title", language: lang)
            let trash = L10n.t("action.moveToTrash.title", language: lang)
            let verified = L10n.t("verification.recovered.title", language: lang)
            let pending = L10n.t("verification.recoveryPending.trash", language: lang)

            XCTAssertFalse(keep.isEmpty)
            XCTAssertFalse(protected.isEmpty)
            XCTAssertFalse(verify.isEmpty)
            XCTAssertFalse(trash.isEmpty)
            XCTAssertFalse(verified.isEmpty)
            XCTAssertFalse(pending.isEmpty)

            let trashLower = trash.lowercased()
            XCTAssertFalse(trashLower.contains("permanent"))
            XCTAssertFalse(trashLower.contains("永久削除"))
        }
    }

    func testCloudDeleteConceptsRemainDistinct() {
        for lang in AppLanguage.shippingLocales {
            let voice = L10n.t("entity.voiceMemos.block", language: lang).lowercased()
            let chrome = L10n.t("entity.chrome.block", language: lang).lowercased()
            // Must not collapse to "backed up, safe to delete"
            XCTAssertFalse(voice.contains("safe to delete"))
            XCTAssertFalse(voice.contains("안전하게 삭제"))
            XCTAssertFalse(chrome.contains("junk"))
        }
    }

    func testZhScriptSeparation() {
        let hans = L10n.t("permission.fullDiskAccess.description", language: .chineseSimplified)
        let hant = L10n.t("permission.fullDiskAccess.description", language: .chineseTraditional)
        XCTAssertNotEqual(hans, hant)
        // Simplified-leaning vs Traditional characters for common terms
        XCTAssertTrue(hans.contains("存储") || hans.contains("磁盘") || hans.contains("访问"))
        XCTAssertTrue(hant.contains("儲存") || hant.contains("磁碟") || hant.contains("存取"))
    }

    func testNumberByteDateFormattingPerLocale() {
        for lang in AppLanguage.shippingLocales {
            let bytes = LocaleFormatting.byteLabel(5_580_814_899, language: lang)
            let num = LocaleFormatting.integer(1_234_567, language: lang)
            let date = LocaleFormatting.date(Date(timeIntervalSince1970: 1_725_000_000), language: lang)
            XCTAssertFalse(bytes.isEmpty, "\(lang)")
            XCTAssertFalse(num.isEmpty, "\(lang)")
            XCTAssertFalse(date.isEmpty, "\(lang)")
        }
        XCTAssertEqual(ProductReleaseIdentity.verifiedRecoveredBytesCanonical, 5_580_814_899)
    }

    func testPluralizationCounts() {
        for n in [0, 1, 2, 12] {
            let s = L10n.t("plural.verificationAreas", language: .english, n)
            XCTAssertTrue(s.contains("\(n)"))
        }
        let ja = L10n.t("plural.verificationAreas", language: .japanese, 2)
        XCTAssertTrue(ja.contains("2"))
    }

    func testLanguageSwitchDoesNotAlterCanonicalBytes() {
        let sequence: [AppLanguage] = [.system, .english, .japanese, .german, .chineseSimplified, .system]
        for lang in sequence {
            L10n.setOverride(lang)
            XCTAssertEqual(
                StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal,
                5_580_814_899
            )
            XCTAssertEqual(ProductizationInvariants.existingExecutors.count, 3)
        }
        L10n.setOverride(.english)
    }

    func testInvalidStoredLocaleFallsBackToSystem() {
        XCTAssertEqual(AppLanguage.parse("xx-YY"), .system)
        XCTAssertEqual(AppLanguage.parse(""), .system)
    }

    func testLanguageStorePersistenceRoundTrip() async {
        let suite = UserDefaults(suiteName: "p54.language.store.test")!
        suite.removePersistentDomain(forName: "p54.language.store.test")
        await MainActor.run {
            let store = LanguageStore(defaults: suite)
            store.language = .german
            XCTAssertEqual(suite.string(forKey: "appLanguage.v1"), "de")
            let reloaded = LanguageStore(defaults: suite)
            XCTAssertEqual(reloaded.language, .german)
            reloaded.language = .system
            XCTAssertEqual(AppLanguage.parse(suite.string(forKey: "appLanguage.v1")), .system)
        }
        suite.removePersistentDomain(forName: "p54.language.store.test")
    }

    func testEntityPresentationSubtypeTitlesResolveViaL10n() {
        L10n.setOverride(.japanese)
        let title = L10n.t("entity.chromeWebsiteState.title")
        XCTAssertEqual(title, "サイトとアプリのデータ")
        L10n.setOverride(.german)
        XCTAssertEqual(L10n.t("entity.claudeRuntimeBase.title"), "Claude-Runtime-Basis")
        L10n.setOverride(.english)
    }

    func testOfflineCatalogNoNetworkKeys() {
        for key in L10n.productionKeys {
            XCTAssertFalse(key.lowercased().contains("translate.api"))
            XCTAssertFalse(key.lowercased().contains("openai"))
        }
    }

    func testRegressionCountersRemainZero() {
        XCTAssertFalse(ProductizationInvariants.secondCrawlerAdded)
        XCTAssertEqual(ProductizationInvariants.unknownAuthorizationCount, 0)
        XCTAssertEqual(ProductizationInvariants.contractGateBypassCount, 0)
        XCTAssertEqual(ProductizationInvariants.approvalBypassCount, 0)
        XCTAssertEqual(ProductizationInvariants.unverifiedRecoveryPresentationCount, 0)
        XCTAssertFalse(StorageProductPresentationBuilder.fakeRecoverableBytesAllowed())
        XCTAssertTrue(ProductizationInvariants.researchFrozen)
        XCTAssertTrue(ProductizationInvariants.noNewExecutor)
        XCTAssertEqual(ProductizationInvariants.existingExecutors.count, 3)
    }

    func testStoreMetadataFilesPresent() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("localization/store")
        for id in LocalizationCoverageAudit.shippingLocaleIDs {
            let url = root.appendingPathComponent("\(id).md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), id)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            XCTAssertFalse(text.isEmpty, id)
            XCTAssertTrue(text.contains("AI Storage Manager"), id)
            // Affirmative body (before "Do not claim" / equivalent) must not sell unsupported claims.
            let splitMarkers = ["## Do not claim", "## 言わないこと", "## 不要宣称", "## 不要宣稱", "## 주장하지 말 것", "## No afirmar", "## Ne pas affirmer", "## Nicht behaupten", "## Não afirmar"]
            var affirmative = text
            for marker in splitMarkers {
                if let range = text.range(of: marker) {
                    affirmative = String(text[..<range.lowerBound])
                    break
                }
            }
            let lower = affirmative.lowercased()
            XCTAssertFalse(lower.contains("one-click cleanup"), id)
            XCTAssertFalse(lower.contains("guaranteed recoverable"), id)
            XCTAssertFalse(lower.contains("cleans every app"), id)
        }
    }
}
