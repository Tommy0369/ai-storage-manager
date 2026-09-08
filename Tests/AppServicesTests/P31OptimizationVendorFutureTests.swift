import XCTest
@testable import AppServices
@testable import SafetyCore

final class P31OptimizationVendorFutureTests: XCTestCase {
    func testVendorNativeUnscopedRemainsNotImplemented() {
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .vendorNativeCleanup), .notImplemented)
    }

    func testOllamaModelExecutorMovesToPreflightNotReadyNow() {
        let fact = OptimizationActionFact(
            entityID: "ai.ollama.model.library.qwen3:4b",
            displayName: "library/qwen3:4b",
            canonicalPath: "/tmp/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b",
            action: .vendorNativeCleanup,
            eligible: true,
            safetyClass: .unknown,
            expectedLogicalBytes: 400,
            explanation: "native"
        )
        let candidate = OptimizationCandidateBuilder.fromFact(fact)
        XCTAssertEqual(candidate.executionSupport, .implemented)
        XCTAssertEqual(candidate.tier, .approvalRequired)
        XCTAssertNotEqual(candidate.tier, .executableNow)
    }

    func testHFVendorNativeMovesOffVerifiedFutureWhenExecutorExists() {
        let fact = OptimizationActionFact(
            entityID: "ai.hf.snapshot.org.m.abc",
            displayName: "org/m@abc",
            canonicalPath: "/tmp/.cache/huggingface/hub/models--org--m/snapshots/abc",
            action: .vendorNativeCleanup,
            eligible: true,
            safetyClass: .unknown,
            expectedLogicalBytes: 3_000_000_000,
            explanation: "hf"
        )
        let candidate = OptimizationCandidateBuilder.fromFact(fact)
        XCTAssertEqual(candidate.executionSupport, .implemented)
        XCTAssertEqual(candidate.tier, .approvalRequired)
        XCTAssertNotEqual(candidate.tier, .executableNow)
        XCTAssertNotEqual(candidate.tier, .verifiedButExecutorUnavailable)
        // Repo-wide / unscoped still unavailable.
        XCTAssertEqual(
            ActionExecutionCapabilityRegistry.support(
                for: .vendorNativeCleanup, vendor: .huggingFace, entityKind: .repository
            ),
            .notImplemented
        )
    }
}
