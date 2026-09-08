import XCTest
@testable import AppServices
@testable import SafetyCore

/// v0.2 UX FIX 001 — lens labels, canonical scan status, native app menu titles.
///
/// These are presentation-only changes. The last test in this file is the one
/// that matters most: locale must never move Safety.
final class V02UXFix001Tests: XCTestCase {

    private var savedLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        savedLanguage = L10n.currentLanguage()
    }

    override func tearDown() {
        L10n.setOverride(savedLanguage)
        super.tearDown()
    }

    // MARK: - Lens labels

    func testLensRawValuesAreUnchanged() {
        // Internal identifiers are domain contract. Presentation must not rename them.
        XCTAssertEqual(StorageMapLens.allCases.map(\.rawValue), ["STRUCTURE", "MEANING", "DECISION"])
        XCTAssertEqual(StorageMapLens.allCases.count, 3)
    }

    func testJapaneseLensLabels() {
        L10n.setOverride(.japanese)
        XCTAssertEqual(StorageMapLens.structure.title, "どこにある？")
        XCTAssertEqual(StorageMapLens.meaning.title, "これは何？")
        XCTAssertEqual(StorageMapLens.decision.title, "どうする？")
    }

    func testEnglishLensLabels() {
        L10n.setOverride(.english)
        XCTAssertEqual(StorageMapLens.structure.title, "Where?")
        XCTAssertEqual(StorageMapLens.meaning.title, "What is it?")
        XCTAssertEqual(StorageMapLens.decision.title, "What can I do?")
    }

    func testLensLabelsTranslatedInEveryShippingLocale() {
        for locale in ["en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR"] {
            for key in ["lens.structure", "lens.meaning", "lens.decision"] {
                let value = L10n.translation(key: key, localeID: locale)
                XCTAssertNotNil(value, "\(key) missing for \(locale)")
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) empty for \(locale)")
            }
        }
        // Non-English locales must actually differ from English for these.
        XCTAssertNotEqual(
            L10n.translation(key: "lens.decision", localeID: "ja"),
            L10n.translation(key: "lens.decision", localeID: "en")
        )
    }

    // MARK: - Canonical scan status

    func testActiveScanResolvesToActive() {
        XCTAssertEqual(
            StorageScanStatusResolver.resolve(stage: .scanningFiles, coverage: .complete),
            .active
        )
        XCTAssertEqual(
            StorageScanStatusResolver.resolve(stage: .hierarchyAvailable, coverage: nil),
            .active
        )
    }

    func testDeepStagesResolveToDeepening() {
        XCTAssertEqual(
            StorageScanStatusResolver.resolve(stage: .understandingStorage, coverage: .complete),
            .deepening
        )
        XCTAssertEqual(
            StorageScanStatusResolver.resolve(stage: .checkingSafety, coverage: .complete),
            .deepening
        )
    }

    /// The reported bug: a partial scan was being presented as a total failure.
    func testPartialCoverageWhileScanningIsNeverPresentedAsFailure() {
        for stage: StorageScanStage in [
            .scanningFiles, .hierarchyAvailable, .understandingStorage, .checkingSafety,
        ] {
            let status = StorageScanStatusResolver.resolve(stage: stage, coverage: .partial)
            XCTAssertEqual(status, .partialContinuing, "stage \(stage)")
            XCTAssertNotEqual(status, .failed, "partial must never read as failed")
            XCTAssertTrue(status.isRunning, "partial+continuing is still in flight")
        }
    }

    func testOnlyAThrownScanErrorIsAFailure() {
        XCTAssertEqual(StorageScanStatusResolver.resolve(stage: .failed, coverage: .partial), .failed)
        XCTAssertEqual(StorageScanStatusResolver.resolve(stage: .failed, coverage: .complete), .failed)
        // A failure is not progress — no spinner.
        XCTAssertFalse(StorageScanStatus.failed.isRunning)
    }

    func testCompleteAndIdleDoNotShowBanner() {
        XCTAssertFalse(StorageScanStatus.complete.showsBanner)
        XCTAssertFalse(StorageScanStatus.idle.showsBanner)
        XCTAssertTrue(StorageScanStatus.failed.showsBanner)
        XCTAssertTrue(StorageScanStatus.partialContinuing.showsBanner)
    }

    func testJapaneseScanCopy() {
        L10n.setOverride(.japanese)
        XCTAssertEqual(StorageScanStatus.active.localizedText, "スキャン中…")
        XCTAssertEqual(StorageScanStatus.deepening.localizedText, "さらに詳しく確認しています…")
        XCTAssertEqual(
            StorageScanStatus.partialContinuing.localizedText,
            "一部を確認できませんでした。残りをスキャンしています…"
        )
        XCTAssertEqual(StorageScanStatus.complete.localizedText, "スキャン完了")
        XCTAssertEqual(StorageScanStatus.failed.localizedText, "スキャンを完了できませんでした")
    }

    func testJapanesePartialCopyIsNotAFailureSentence() {
        L10n.setOverride(.japanese)
        let partial = StorageScanStatus.partialContinuing.localizedText
        XCTAssertTrue(partial.contains("スキャンしています"), partial)
        XCTAssertFalse(partial.contains("失敗"), "partial copy must not say failed: \(partial)")
    }

    func testEnglishScanCopy() {
        L10n.setOverride(.english)
        XCTAssertEqual(StorageScanStatus.active.localizedText, "Scanning…")
        XCTAssertEqual(StorageScanStatus.complete.localizedText, "Scan complete")
        XCTAssertFalse(
            StorageScanStatus.partialContinuing.localizedText.lowercased().contains("failed")
        )
    }

    /// While the status sentence already says coverage was partial, the chip
    /// must not repeat it; once the scan stops, the caveat stands on its own.
    func testPartialCoverageNoteIsNotDuplicatedWhileRunning() {
        XCTAssertNil(
            StorageScanStatusResolver.partialCoverageNote(stage: .scanningFiles, coverage: .partial)
        )
        XCTAssertNotNil(
            StorageScanStatusResolver.partialCoverageNote(stage: .complete, coverage: .partial)
        )
        XCTAssertNil(
            StorageScanStatusResolver.partialCoverageNote(stage: .complete, coverage: .complete)
        )
    }

    // MARK: - Native app menu titles

    func testJapaneseAppMenuTitles() {
        let name = "AI Storage Manager"
        func t(_ kind: AppMenuItemKind) -> String {
            AppMenuTitles.title(for: kind, language: .japanese, appName: name)
        }
        XCTAssertEqual(t(.about), "AI Storage Managerについて")
        XCTAssertEqual(t(.services), "サービス")
        XCTAssertEqual(t(.hide), "AI Storage Managerを非表示")
        XCTAssertEqual(t(.hideOthers), "ほかを非表示")
        XCTAssertEqual(t(.showAll), "すべてを表示")
        XCTAssertEqual(t(.quit), "AI Storage Managerを終了")
    }

    func testEnglishAppMenuTitles() {
        let name = "AI Storage Manager"
        func t(_ kind: AppMenuItemKind) -> String {
            AppMenuTitles.title(for: kind, language: .english, appName: name)
        }
        XCTAssertEqual(t(.about), "About AI Storage Manager")
        XCTAssertEqual(t(.services), "Services")
        XCTAssertEqual(t(.hide), "Hide AI Storage Manager")
        XCTAssertEqual(t(.hideOthers), "Hide Others")
        XCTAssertEqual(t(.showAll), "Show All")
        XCTAssertEqual(t(.quit), "Quit AI Storage Manager")
    }

    /// §16: for the NATIVE MENU ONLY, Japanese gets Japanese and everything else
    /// gets English. The product UI stays 9-locale — asserted by P5.3/P5.4.
    func testNonJapaneseLanguagesFallBackToEnglishMenu() {
        let name = "AI Storage Manager"
        for language in AppLanguage.allCases where language != .japanese && language != .system {
            XCTAssertFalse(
                AppMenuTitles.usesJapanese(language),
                "\(language.rawValue) must use the English menu"
            )
            XCTAssertEqual(
                AppMenuTitles.title(for: .quit, language: language, appName: name),
                "Quit AI Storage Manager",
                language.rawValue
            )
        }
        XCTAssertTrue(AppMenuTitles.usesJapanese(.japanese))
    }

    /// `.system` must follow the EFFECTIVE locale, not the enum case.
    ///
    /// On a Japanese Mac the whole product UI renders in Japanese while the app
    /// language is still `.system` — an English app menu there is exactly the
    /// mismatch this fix removes. So the rule keys off the resolved catalog
    /// locale, which is also why this assertion is machine-independent.
    func testSystemLanguageFollowsTheEffectiveLocale() {
        let systemIsJapanese = L10n.catalogLocaleID(for: .system) == "ja"
        XCTAssertEqual(
            AppMenuTitles.usesJapanese(.system),
            systemIsJapanese,
            "the native menu must match whatever language the product UI actually renders"
        )
        let title = AppMenuTitles.title(for: .quit, language: .system, appName: "AI Storage Manager")
        XCTAssertEqual(
            title,
            systemIsJapanese ? "AI Storage Managerを終了" : "Quit AI Storage Manager"
        )
    }

    /// Quit and its Option-key alternate share `terminate:`. If they were told
    /// apart by selector alone, both would end up labelled "Quit".
    func testQuitAlternateIsADistinctItem() {
        XCTAssertEqual(AppMenuItemKind.quit.selectorName, "terminate:")
        XCTAssertEqual(AppMenuItemKind.quitKeepingWindows.selectorName, "terminate:")
        XCTAssertNotEqual(
            AppMenuTitles.title(for: .quit, language: .japanese, appName: "X"),
            AppMenuTitles.title(for: .quitKeepingWindows, language: .japanese, appName: "X")
        )
        XCTAssertEqual(
            AppMenuTitles.title(for: .quitKeepingWindows, language: .japanese, appName: "X"),
            "ウインドウを残して終了"
        )
        XCTAssertEqual(
            AppMenuTitles.title(for: .quitKeepingWindows, language: .english, appName: "X"),
            "Quit and Keep Windows"
        )
    }

    func testMenuItemsAreIdentifiedBySelectorNotTitle() {
        // Title matching breaks as soon as the title is localized, so every
        // rewritable item must carry a stable selector.
        XCTAssertEqual(AppMenuItemKind.about.selectorName, "orderFrontStandardAboutPanel:")
        XCTAssertEqual(AppMenuItemKind.hide.selectorName, "hide:")
        XCTAssertEqual(AppMenuItemKind.hideOthers.selectorName, "hideOtherApplications:")
        XCTAssertEqual(AppMenuItemKind.showAll.selectorName, "unhideAllApplications:")
        XCTAssertEqual(AppMenuItemKind.quit.selectorName, "terminate:")
        // Services is matched by NSApplication.servicesMenu identity instead.
        XCTAssertNil(AppMenuItemKind.services.selectorName)
    }

    // MARK: - Top-bar copy

    func testLargestFolderStoryIsLocalized() {
        let ja = L10n.t("story.largestFolder", language: .japanese, ".colima", "10.1 GB")
        XCTAssertTrue(ja.contains(".colima"), ja)
        XCTAssertTrue(ja.contains("10.1 GB"), ja)
        XCTAssertTrue(ja.contains("もっとも大きい"), ja)
        XCTAssertFalse(ja.contains("largest mapped folder"), "English leaked into Japanese: \(ja)")

        let en = L10n.t("story.largestFolder", language: .english, ".colima", "10.1 GB")
        XCTAssertTrue(en.contains("largest mapped folder"), en)
    }

    func testInThisFolderIsLocalized() {
        XCTAssertEqual(L10n.translation(key: "map.inThisFolder", localeID: "ja"), "このフォルダ直下")
        XCTAssertEqual(L10n.translation(key: "map.inThisFolder", localeID: "en"), "In this folder")
    }

    // MARK: - Safety must not move with locale

    func testLocaleChangeDoesNotAlterSafetyOrAccounting() {
        let recoveryByLanguage: [Int64] = AppLanguage.allCases.map { language in
            L10n.setOverride(language)
            return StorageProductPresentationBuilder.verifiedCompletedRecoveryTotal
        }
        // Canonical verified recovery is a fact, not a presentation choice.
        for value in recoveryByLanguage {
            XCTAssertEqual(value, 5_580_814_899, "verified recovery moved with locale")
        }

        // Research freeze and executor semantics are locale-independent.
        for language in AppLanguage.allCases {
            L10n.setOverride(language)
            XCTAssertTrue(ProductizationInvariants.researchFrozen, language.rawValue)
            XCTAssertEqual(
                StorageMapLens.allCases.map(\.rawValue),
                ["STRUCTURE", "MEANING", "DECISION"],
                language.rawValue
            )
        }
    }

    func testScanStatusIsPresentationOnlyAndTotal() {
        // Every (stage, coverage) pair must resolve — no unhandled state can
        // leak an English fallback or an empty banner.
        let coverages: [PhysicalMapCoverage?] = [nil, .complete, .partial, .unknown]
        let stages: [StorageScanStage] = [
            .idle, .scanningFiles, .hierarchyAvailable,
            .understandingStorage, .checkingSafety, .complete, .failed,
        ]
        L10n.setOverride(.japanese)
        for stage in stages {
            for coverage in coverages {
                let status = StorageScanStatusResolver.resolve(stage: stage, coverage: coverage)
                XCTAssertFalse(
                    status.localizedText.isEmpty,
                    "empty copy for \(stage)/\(String(describing: coverage))"
                )
                XCTAssertNotEqual(
                    status.localizedText,
                    status.localizationKey,
                    "missing translation for \(status.rawValue)"
                )
            }
        }
    }

    // MARK: - Split divider layout ownership

    /// The reported bug was two identical-looking vertical rules where only one
    /// was a real pane boundary: `HStack { map; Divider(); inspector.frame(width: 320) }`
    /// drew a separator while the boundary lived in a hardcoded width.
    ///
    /// A unit test cannot see pixels, so this guards the *ownership* instead:
    /// the map/inspector boundary must be a native split, never a decorative
    /// line plus a fixed frame. Visual confirmation is a separate, mandatory step.
    func testMapSplitBoundaryHasASingleNativeOwner() throws {
        let root = FileManager.default.currentDirectoryPath
        let path = root + "/Sources/AIStorageManagerUI/Explorer/StorageExplorerView.swift"
        let source = try String(contentsOfFile: path, encoding: .utf8)

        guard let start = source.range(of: "private func mapSplit(") else {
            return XCTFail("mapSplit not found — update this guard if the view was renamed")
        }
        guard let end = source.range(of: "private func largestList(", range: start.upperBound..<source.endIndex) else {
            return XCTFail("could not bound mapSplit body")
        }
        let body = String(source[start.upperBound..<end.lowerBound])

        XCTAssertTrue(
            body.contains("HSplitView"),
            "map/inspector boundary must be a native split so the visible line IS the draggable boundary"
        )
        XCTAssertFalse(
            body.contains("Divider()"),
            "a decorative Divider() inside the split duplicates the native separator and reads as a ghost line"
        )
        XCTAssertFalse(
            body.contains(".frame(width:"),
            "a hardcoded pane width makes the boundary unadjustable while still looking draggable"
        )
        // The inspector must stay resizable within bounds rather than pinned.
        XCTAssertTrue(body.contains("minWidth:"), "split panes need min widths so neither can vanish")
        XCTAssertTrue(body.contains("idealWidth:"), "inspector needs an ideal width to restore sane defaults")
    }

    // MARK: - Settings pane layout

    /// Live Settings used `Form { … }.frame(maxHeight: .infinity, alignment: .topLeading)`
    /// inside NavigationSplitView's content column. Title updated, pane stayed blank
    /// (also seen under ImageRenderer in P5.4). Guard the ownership of layout:
    /// Settings must scroll with intrinsic height, not a collapsing Form.
    func testSettingsPaneDoesNotUseCollapsingFormLayout() throws {
        let root = FileManager.default.currentDirectoryPath
        let path = root + "/Sources/AIStorageManagerUI/AppShellView.swift"
        let source = try String(contentsOfFile: path, encoding: .utf8)

        guard let start = source.range(of: "private struct SettingsDebugGateView") else {
            return XCTFail("SettingsDebugGateView not found")
        }
        let body = String(source[start.lowerBound...])

        XCTAssertTrue(
            body.contains("ScrollView"),
            "Settings must use ScrollView so content has intrinsic height in the split content column"
        )
        XCTAssertFalse(
            body.contains("Form {"),
            "Form + maxHeight infinity collapses to a blank Settings pane on macOS NavigationSplitView"
        )
        XCTAssertTrue(
            body.contains("settings.language"),
            "language picker section must remain present"
        )
        XCTAssertTrue(
            body.contains("$languageStore.language"),
            "language binding must remain reachable from Settings"
        )
    }
}
