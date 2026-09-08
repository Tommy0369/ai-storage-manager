import XCTest
@testable import SafetyCore
@testable import AppServices

final class P311RemoteReacquisitionTests: XCTestCase {
    private lazy var engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))

    override func setUp() {
        super.setUp()
        RemoteReacquisitionProofIndex.reset()
        VendorStorageProofIndex.reset()
    }

    func testHFPublicExactRevisionVerified() {
        let mock = MockRemoteHTTPTransport()
        mock.handlers["hf|rev|org/alpha|abc123"] = { _ in
            RemoteHTTPResponse(statusCode: 200, body: Data(#"{"sha":"abc123"}"#.utf8))
        }
        let session = RemoteRequestSession(transport: mock)
        let entity = hfEntity(repo: "org/alpha", rev: "abc123", bytes: 100)
        let proof = HuggingFaceRemoteVerifier().verify(entity: entity, session: session)
        XCTAssertEqual(proof.status, .verified)
        XCTAssertEqual(proof.confidence, .verified)
        XCTAssertTrue(proof.isStrictVerified)
        XCTAssertEqual(proof.authenticationClass, .anonymous)
        XCTAssertEqual(mock.calls.count, 1)
    }

    func testHFRevisionUnavailableNotLatestFallback() {
        let mock = MockRemoteHTTPTransport()
        mock.handlers["hf|rev|org/alpha|deadbeef"] = { _ in RemoteHTTPResponse(statusCode: 404) }
        mock.handlers["hf|head|org/alpha|deadbeef|config.json"] = { _ in RemoteHTTPResponse(statusCode: 404) }
        let session = RemoteRequestSession(transport: mock)
        let entity = hfEntity(repo: "org/alpha", rev: "deadbeef", bytes: 50)
        let proof = HuggingFaceRemoteVerifier().verify(entity: entity, session: session)
        XCTAssertEqual(proof.status, .identityMismatch)
        XCTAssertNotEqual(proof.status, .verified)
        XCTAssertEqual(proof.failureReason, "EXACT_REVISION_NOT_FOUND")
    }

    func testHFAuthRemainsUnknown() {
        let mock = MockRemoteHTTPTransport()
        mock.handlers["hf|rev|org/gated|c1"] = { _ in RemoteHTTPResponse(statusCode: 401) }
        let session = RemoteRequestSession(transport: mock)
        let proof = HuggingFaceRemoteVerifier().verify(entity: hfEntity(repo: "org/gated", rev: "c1", bytes: 10), session: session)
        XCTAssertEqual(proof.status, .authRequired)
        XCTAssertEqual(proof.confidence, .unknown)
        XCTAssertNotEqual(proof.status, .verified)
    }

    func testHFTimeoutUnknown() {
        let mock = MockRemoteHTTPTransport()
        mock.handlers["hf|rev|org/slow|c1"] = { _ in RemoteHTTPResponse(statusCode: 0, timedOut: true, errorKind: "TIMEOUT") }
        let session = RemoteRequestSession(transport: mock)
        let proof = HuggingFaceRemoteVerifier().verify(entity: hfEntity(repo: "org/slow", rev: "c1", bytes: 10), session: session)
        XCTAssertEqual(proof.status, .timeout)
        XCTAssertEqual(proof.confidence, .unknown)
    }

    func testOllamaExactManifestVerified() {
        let digests = ["sha256-aaa", "sha256-bbb"]
        let body = manifestJSON(digests: digests)
        let mock = MockRemoteHTTPTransport()
        mock.handlers["ollama|manifest|library|qwen3|4b"] = { _ in RemoteHTTPResponse(statusCode: 200, body: body) }
        let session = RemoteRequestSession(transport: mock)
        var entity = ollamaEntity(display: "library/qwen3:4b", digests: digests, bytes: 200)
        entity.canonicalPath = "/tmp/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let proof = OllamaRemoteVerifier().verify(entity: entity, session: session)
        XCTAssertEqual(proof.status, .verified)
        XCTAssertEqual(proof.confidence, .verified)
    }

    func testOllamaTagDriftIdentityMismatch() {
        let local = ["sha256-old1", "sha256-old2"]
        let remote = ["sha256-new1", "sha256-new2"]
        let mock = MockRemoteHTTPTransport()
        mock.handlers["ollama|manifest|library|qwen3|4b"] = { _ in
            RemoteHTTPResponse(statusCode: 200, body: self.manifestJSON(digests: remote))
        }
        let session = RemoteRequestSession(transport: mock)
        var entity = ollamaEntity(display: "library/qwen3:4b", digests: local, bytes: 200)
        entity.canonicalPath = "/tmp/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b"
        let proof = OllamaRemoteVerifier().verify(entity: entity, session: session)
        XCTAssertEqual(proof.status, .identityMismatch)
        XCTAssertEqual(proof.failureReason, "TAG_POINTS_TO_DIFFERENT_MANIFEST")
        XCTAssertNotEqual(proof.status, .verified)
    }

    func testOllamaCustomNotApplicable() {
        let session = RemoteRequestSession(transport: MockRemoteHTTPTransport())
        var entity = ollamaEntity(display: "local/custom:latest", digests: ["sha256-x"], bytes: 10)
        entity.isUserOriginalSuspect = true
        entity.originIdentity = "local"
        let proof = OllamaRemoteVerifier().verify(entity: entity, session: session)
        XCTAssertEqual(proof.status, .notApplicable)
        XCTAssertEqual(session.stats.requests, 0)
    }

    func testHTTPStatusVendorAware() {
        let cases: [(Int, RemoteReacquisitionStatus)] = [
            (200, .verified),
            (401, .authRequired),
            (403, .authRequired),
            (404, .identityMismatch),
            (429, .rateLimited),
            (500, .unknown)
        ]
        for (code, expected) in cases {
            let mock = MockRemoteHTTPTransport()
            mock.handlers["hf|rev|org/x|r"] = { _ in
                if code == 200 {
                    return RemoteHTTPResponse(statusCode: 200, body: Data(#"{"sha":"r"}"#.utf8))
                }
                return RemoteHTTPResponse(statusCode: code)
            }
            let proof = HuggingFaceRemoteVerifier().verify(
                entity: hfEntity(repo: "org/x", rev: "r", bytes: 1),
                session: RemoteRequestSession(transport: mock)
            )
            XCTAssertEqual(proof.status, expected, "status \(code)")
        }
    }

    func testFreshnessExpiryInvalidatesStrict() {
        var proof = RemoteReacquisitionProof(
            vendor: .huggingFace,
            entityID: "e1",
            localIdentity: "org/x@r",
            remoteIdentity: "org/x",
            remoteRevisionOrDigest: "r",
            status: .verified,
            verifiedAt: Date().addingTimeInterval(-10_000),
            freshUntil: Date().addingTimeInterval(-1),
            authenticationClass: .anonymous,
            proofMethod: .hfRevisionAPI,
            confidence: .verified,
            endpointClass: "huggingface.hub"
        )
        XCTAssertFalse(proof.isFresh)
        XCTAssertFalse(proof.isStrictVerified)
        var v = VerificationAnnotation()
        RemoteReacquisitionService.apply(proof: proof, to: &v)
        XCTAssertNotEqual(v.reacquisition.confidence, .verified)
        XCTAssertEqual(v.reacquisition.reasonCode, "REMOTE_PROOF_STALE")
    }

    func testVendorNativeVerifiedFutureNotReadyNow() {
        var item = classified(id: "ai.hf.repo.org.alpha", path: "/tmp/.cache/huggingface/hub/models--org--alpha", bytes: 3_000)
        let proof = RemoteReacquisitionProof(
            vendor: .huggingFace,
            entityID: item.detected.entity.id,
            localIdentity: "org/alpha@abc",
            remoteIdentity: "org/alpha",
            remoteRevisionOrDigest: "abc",
            status: .verified,
            freshUntil: Date().addingTimeInterval(900),
            authenticationClass: .anonymous,
            proofMethod: .mock,
            confidence: .verified,
            estimatedRedownloadBytes: 3_000,
            endpointClass: "huggingface.hub"
        )
        item.verification = VerificationAnnotation(
            uniqueBytesProven: 3_000,
            referenceGraphConfidence: .verified,
            reacquisition: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .vendorRule),
            remoteReacquisitionProof: proof,
            estimatedRedownloadBytes: 3_000
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .vendorNativeCleanup,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertTrue(decision.eligible)
        XCTAssertEqual(item.decision.safetyClass, .unknown)
        XCTAssertEqual(ActionExecutionCapabilityRegistry.support(for: .vendorNativeCleanup), .notImplemented)

        let fact = OptimizationActionFact(
            entityID: item.detected.entity.id,
            displayName: "org/alpha",
            canonicalPath: item.detected.entity.path,
            action: .vendorNativeCleanup,
            eligible: true,
            safetyClass: .unknown,
            expectedLogicalBytes: 3_000,
            explanation: "remote verified"
        )
        let candidate = OptimizationCandidateBuilder.fromFact(fact)
        XCTAssertEqual(candidate.tier, .verifiedButExecutorUnavailable)
        XCTAssertNotEqual(candidate.tier, .executableNow)
    }

    func testRemoteAloneDoesNotBypassUserOriginal() {
        var item = classified(id: "ai.ollama.model.local.custom", path: "/tmp/.ollama/models/manifests/local/custom/x", bytes: 10)
        item.verification = VerificationAnnotation(
            vendorProofNotes: ["USER_ORIGINAL_OR_CUSTOM_MODEL_SUSPECT"],
            uniqueBytesProven: 10,
            referenceGraphConfidence: .verified,
            reacquisition: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .vendorRule),
            remoteReacquisitionProof: RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: item.detected.entity.id,
                localIdentity: "custom",
                status: .verified,
                freshUntil: Date().addingTimeInterval(900),
                authenticationClass: .anonymous,
                proofMethod: .mock,
                confidence: .verified,
                endpointClass: "ollama.registry"
            )
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .vendorNativeCleanup,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.userOriginalRequiresPreservation))
    }

    func testRawBlobStillBlocked() {
        var item = classified(id: "ai.ollama.blobs", path: "/tmp/.ollama/models/blobs", bytes: 99)
        item.verification = VerificationAnnotation(
            uniqueBytesProven: 99,
            referenceGraphConfidence: .verified,
            reacquisition: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .vendorRule)
        )
        let trash = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertFalse(trash.eligible)
        let vendor = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .vendorNativeCleanup,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertFalse(vendor.eligible)
    }

    // MARK: helpers

    private func hfEntity(repo: String, rev: String, bytes: Int64) -> VendorSemanticEntity {
        VendorSemanticEntity(
            vendor: .huggingFace,
            entityKind: .snapshot,
            entityID: "ai.hf.snapshot.\(repo.replacingOccurrences(of: "/", with: ".")).",
            displayIdentity: "\(repo)@\(rev)",
            canonicalPath: "/tmp/hf/\(repo)/snapshots/\(rev)",
            logicalBytes: bytes,
            uniqueBytes: bytes,
            sharedBytes: 0,
            originIdentity: repo,
            revisionIdentity: rev,
            referenceScope: .exclusive,
            referenceGraphComplete: true,
            runtimeState: .unknown,
            runtimeConfidence: .unknown,
            reacquisition: .remoteAvailabilityUnknown,
            reacquisitionConfidence: .unknown,
            provenanceConfidence: .verified,
            isUserOriginalSuspect: false,
            referencedBlobDigests: ["b1"],
            topBlockers: [],
            preferredActionHint: .vendorNativeCleanup,
            notes: []
        )
    }

    private func ollamaEntity(display: String, digests: [String], bytes: Int64) -> VendorSemanticEntity {
        VendorSemanticEntity(
            vendor: .ollama,
            entityKind: .model,
            entityID: "ai.ollama.model.\(display)",
            displayIdentity: display,
            canonicalPath: "/tmp/.ollama/models/manifests/registry.ollama.ai/\(display.replacingOccurrences(of: ":", with: "/"))",
            logicalBytes: bytes,
            uniqueBytes: bytes,
            sharedBytes: 0,
            originIdentity: "registry.ollama.ai",
            revisionIdentity: display,
            referenceScope: .exclusive,
            referenceGraphComplete: true,
            runtimeState: .unknown,
            runtimeConfidence: .unknown,
            reacquisition: .remoteAvailabilityUnknown,
            reacquisitionConfidence: .unknown,
            provenanceConfidence: .verified,
            isUserOriginalSuspect: false,
            referencedBlobDigests: digests,
            topBlockers: [],
            preferredActionHint: .vendorNativeCleanup,
            notes: []
        )
    }

    private func manifestJSON(digests: [String]) -> Data {
        var layers: [[String: Any]] = []
        for d in digests.dropFirst() {
            layers.append(["digest": d.replacingOccurrences(of: "sha256-", with: "sha256:"), "size": 1])
        }
        let payload: [String: Any] = [
            "schemaVersion": 2,
            "config": ["digest": digests[0].replacingOccurrences(of: "sha256-", with: "sha256:"), "size": 1],
            "layers": layers.isEmpty ? [["digest": digests[0].replacingOccurrences(of: "sha256-", with: "sha256:"), "size": 1]] : layers
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func classified(id: String, path: String, bytes: Int64) -> ClassifiedItem {
        let entity = StorageEntity(id: id, kind: .cache, category: "AI_DEV", subcategory: id, displayName: id, path: path, logicalBytes: bytes)
        let detected = DetectedEntity(entity: entity, bucket: .developer, domain: "AI Tools", associatedProcesses: [], identified: true, annotation: nil)
        let decision = SafetyDecision(
            entity: entity, action: .noAction, safetyClass: .unknown, safetyScore: nil,
            reasonCodes: [], sideEffects: [], matchedRuleID: nil, evaluationLayer: .unknownFallback,
            evidenceConfidence: 0, userExplanationJA: "t", growthCauses: [], requiresUserApproval: true, blockedBy: nil
        )
        return ClassifiedItem(
            detected: detected, decision: decision, semantic: SemanticResult(from: decision),
            allocatedBytes: bytes, actionVariants: [:], inclusiveBytes: bytes, exclusiveBytes: bytes,
            resolution: .l3Product, unknownReason: nil, verification: nil
        )
    }
}
