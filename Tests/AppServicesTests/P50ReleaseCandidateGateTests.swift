import XCTest
@testable import SafetyCore
@testable import AppServices

final class P50ReleaseCandidateGateTests: XCTestCase {

    func testProductIdentityStable() {
        XCTAssertEqual(ProductReleaseIdentity.productName, "AI Storage Manager")
        XCTAssertEqual(ProductReleaseIdentity.releaseVersion, "0.2.0")
        XCTAssertEqual(ProductReleaseIdentity.buildNumber, "51")
        XCTAssertEqual(ProductReleaseIdentity.bundleIdentifier, "com.tomystudio.aistoragemanager")
        XCTAssertEqual(ProductReleaseIdentity.minimumMacOSVersion, "13.0")
        XCTAssertEqual(ProductReleaseIdentity.supportedArchitectures, ["arm64"])
        XCTAssertEqual(ProductReleaseIdentity.verifiedRecoveredBytesCanonical, 2_497_293_931 &+ 3_083_520_968)
        XCTAssertEqual(ProductReleaseIdentity.existingExecutors.count, 3)
    }

    func testCanonicalRecoverySumExact() {
        XCTAssertEqual(
            VerifiedActionResultBuilder.completedVerifiedRecoveryTotal(),
            ProductReleaseIdentity.verifiedRecoveredBytesCanonical
        )
    }

    func testLocalBetaWhenUnsigned() {
        let input = ReleaseCandidateGateInput(
            buildPass: true,
            testsPass: true,
            signed: false,
            notarized: false,
            notarizationCredentialsAvailable: false,
            gatekeeperReady: false
        )
        let result = ReleaseCandidateGate.evaluate(input)
        XCTAssertEqual(result.overallStatus, .rcPassLocalBetaReady)
        XCTAssertFalse(result.liveMutationValidationRequired)
        XCTAssertEqual(result.recommendedNextPhase, "P5.1_SIGN_NOTARIZE_PACKAGE")
        XCTAssertTrue(result.manualRequired.contains { $0.contains("NOTARIZATION") || $0.contains("SIGNING") })
    }

    func testPendingNotarizationWhenSignedOnly() {
        let input = ReleaseCandidateGateInput(
            buildPass: true,
            testsPass: true,
            signed: true,
            notarized: false,
            notarizationCredentialsAvailable: true,
            gatekeeperReady: false
        )
        let result = ReleaseCandidateGate.evaluate(input)
        XCTAssertEqual(result.overallStatus, .rcPassPendingNotarization)
    }

    func testExternalReadyWhenNotarized() {
        let input = ReleaseCandidateGateInput(
            buildPass: true,
            testsPass: true,
            signed: true,
            notarized: true,
            notarizationCredentialsAvailable: true,
            gatekeeperReady: true
        )
        let result = ReleaseCandidateGate.evaluate(input)
        XCTAssertEqual(result.overallStatus, .rcPassExternalDistributionReady)
        XCTAssertEqual(result.recommendedNextPhase, "P5.1_RELEASE_FREEZE_AND_V0_1")
    }

    func testFalseGreenBlocksRC() {
        var input = ReleaseCandidateGateInput(buildPass: true, testsPass: true)
        input.falseGreen = 1
        let result = ReleaseCandidateGate.evaluate(input)
        XCTAssertEqual(result.overallStatus, .rcBlocked)
    }

    func testUnknownAuthorizationBlocksRC() {
        var input = ReleaseCandidateGateInput(buildPass: true, testsPass: true)
        input.unknownAuthorizationCount = 1
        XCTAssertEqual(ReleaseCandidateGate.evaluate(input).overallStatus, .rcBlocked)
    }

    func testSecretsShippedBlocksRC() {
        var input = ReleaseCandidateGateInput(buildPass: true, testsPass: true)
        input.secretsShipped = true
        XCTAssertEqual(ReleaseCandidateGate.evaluate(input).overallStatus, .rcBlocked)
    }

    func testNoMutationAutoRetryInvariant() {
        XCTAssertFalse(ReleaseCandidateGate.mutationAutoRetryAllowed)
        XCTAssertFalse(ReleaseCandidateGate.approvalSurvivesRestart)
        XCTAssertFalse(ReleaseCandidateGate.liveMutationRequiredByDefault)
    }

    func testResearchStillFrozen() {
        XCTAssertTrue(FoundationResearchFreeze.isFrozen)
    }

    func testRiskyClaimPatternsDetected() {
        let risky = [
            "always safe to delete",
            "automatic cleanup of everything",
            "100% recoverable",
            "Free 14GB now",
        ]
        for claim in risky {
            XCTAssertTrue(ProductClaimAudit.containsRiskyUnqualifiedClaim(claim), claim)
        }
        XCTAssertFalse(ProductClaimAudit.containsRiskyUnqualifiedClaim("Keep — these are your recordings."))
        XCTAssertFalse(ProductClaimAudit.containsRiskyUnqualifiedClaim("5.58GB verified recovered"))
    }
}
