import XCTest
@testable import AppServices
@testable import SafetyCore

/// P5.5 — permanent packaging regression: repo translations ≠ shipping .app resources.
final class P55GlobalReleasePackagingTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var packagedApp: URL {
        repoRoot.appendingPathComponent("dist/AI Storage Manager.app")
    }

    func testRepoCatalogExistsButMustNotImplyShipping() {
        let repoCatalog = repoRoot
            .appendingPathComponent("Sources/AppServices/Resources/Localization/LocalizationCatalog.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoCatalog.path))
        // Historical failure mode reminder: repo presence alone is insufficient.
        XCTAssertNotEqual(repoCatalog.path, packagedApp.appendingPathComponent("Contents").path)
    }

    func testMissingShippingCatalogIsDetectedAsFailureMode() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("p55-empty-app-\(UUID().uuidString).app")
        let contents = tmp.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let script = repoRoot.appendingPathComponent("scripts/validate-localization-bundle.sh")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script.path, tmp.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        XCTAssertNotEqual(proc.terminationStatus, 0, "missing catalog must fail validation before signing")
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("SHIPPING_APP_LOCALIZATION_RESOURCES_PRESENT=false") || out.contains("missing"))
    }

    func testPackagedAppLocalizationResourcesWhenDistPresent() throws {
        guard FileManager.default.fileExists(atPath: packagedApp.path) else {
            throw XCTSkip("dist app not present in this environment")
        }
        let candidates = [
            packagedApp.appendingPathComponent("Contents/Resources/Localization/LocalizationCatalog.json"),
            packagedApp.appendingPathComponent("Contents/MacOS/AIStorageManager_AppServices.bundle/LocalizationCatalog.json"),
        ]
        let catalogURL = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertNotNil(catalogURL, "SHIPPING_APP_LOCALIZATION_RESOURCES_PRESENT required")
        let data = try Data(contentsOf: catalogURL!)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let locales = obj?["locales"] as? [String] ?? []
        let expected = LocalizationCoverageAudit.shippingLocaleIDs
        XCTAssertEqual(Set(locales), Set(expected))
        let strings = obj?["strings"] as? [String: [String: String]] ?? [:]
        XCTAssertFalse(strings.isEmpty)
        XCTAssertEqual(strings["decision.keep.title"]?["ja"], "残す")
        XCTAssertNotEqual(strings["decision.keep.title"]?["ja"], strings["decision.keep.title"]?["en"])
    }

    func testReleaseOrderInvariantScriptsExist() {
        let validate = repoRoot.appendingPathComponent("scripts/validate-localization-bundle.sh")
        let package = repoRoot.appendingPathComponent("scripts/package-release-app.sh")
        let notarize = repoRoot.appendingPathComponent("scripts/notarize-release.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: validate.path))
        let packageText = (try? String(contentsOf: package, encoding: .utf8)) ?? ""
        let notarizeText = (try? String(contentsOf: notarize, encoding: .utf8)) ?? ""
        XCTAssertTrue(packageText.contains("validate-localization-bundle.sh"))
        XCTAssertTrue(notarizeText.contains("validate-localization-bundle.sh"))
        XCTAssertTrue(notarizeText.contains("NO_RELEASE_SIGNING_WITHOUT_LOCALIZATION_BUNDLE_VALIDATION")
            || notarizeText.contains("Localization bundle validation"))
    }

    func testExecutorAndRecoveryFrozen() {
        XCTAssertEqual(ProductizationInvariants.existingExecutors.count, 3)
        XCTAssertEqual(ProductReleaseIdentity.verifiedRecoveredBytesCanonical, 5_580_814_899)
        XCTAssertTrue(FoundationResearchFreeze.isFrozen)
        XCTAssertFalse(ProductizationInvariants.secondCrawlerAdded)
    }
}
