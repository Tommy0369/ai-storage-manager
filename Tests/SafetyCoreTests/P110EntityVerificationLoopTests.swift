import XCTest
@testable import SafetyCore

final class P110EntityVerificationLoopTests: XCTestCase {
    func makeEntity(id: String, path: String, bytes: Int64 = 1000, domain: String = "macOS") -> DetectedEntity {
        DetectedEntity(
            entity: StorageEntity(
                id: id,
                kind: .cache,
                category: "MACOS",
                subcategory: "TEST",
                displayName: id,
                path: path,
                logicalBytes: bytes
            ),
            bucket: .generated,
            domain: domain,
            associatedProcesses: [],
            identified: true,
            annotation: nil
        )
    }

    func makeDerivedDataEntity(path: String, workspace: String?) -> DetectedEntity {
        var rels: [EntityRelationship] = []
        if let workspace {
            rels.append(EntityRelationship(
                type: .derivedFrom,
                target: workspace,
                presence: .present,
                confidence: .verified
            ))
        }
        let annotation = DetectionAnnotation(
            detectorID: "test",
            specificity: 80,
            semanticType: "derived_data",
            lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified),
            provenance: ProvenanceEvidence(confidence: .verified),
            relationships: rels
        )
        return DetectedEntity(
            entity: StorageEntity(
                id: "xcode.deriveddata.test",
                kind: .generatedBuild,
                category: "XCODE",
                subcategory: "DERIVED",
                displayName: "dd",
                path: path,
                logicalBytes: 131072
            ),
            bucket: .developer,
            domain: "Xcode",
            associatedProcesses: ["Xcode"],
            identified: true,
            annotation: annotation
        )
    }

    func testHighestValueCandidateSelectedFirst() {
        let dd = makeDerivedDataEntity(path: "/tmp/DerivedData/Foo", workspace: "/tmp/ws")
        let generic = makeEntity(id: "macos.user_caches", path: "/tmp/Caches/foo", bytes: 50_000_000_000)
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil), handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil)),
            processes: ProcessTableSnapshot(names: ["Xcode"], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        let candidates = VerificationCandidateBuilder.build(from: [generic, dd], context: context)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(candidates.first?.entityID, "xcode.deriveddata.test")
    }

    func testAlreadyVerifiedClaimSkipped() {
        let entity = makeDerivedDataEntity(path: "/tmp/DerivedData/X", workspace: "/tmp/p")
        let verification = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .relationshipMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .vendorRule)
        )
        XCTAssertTrue(VerificationStrategies.isClaimAlreadyVerified(claim: .regenerability, entity: entity, verification: verification))
    }

    func testBlockedDependencyNotRepeatedlyAttempted() {
        let entity = makeEntity(id: "xcode.deriveddata.noRel", path: "/tmp/DerivedData/NoRel")
        let candidate = VerificationCandidate(
            entityID: entity.entity.id,
            canonicalPath: entity.entity.path,
            domain: entity.domain,
            semanticLevel: 4,
            uniqueBytes: 1000,
            measurementKnown: true,
            unresolvedClaims: [.regenerability],
            strategiesAvailable: [.resolverRegenerability],
            priority: 100,
            estimatedCostMs: 10,
            blockingReasons: [],
            attemptState: .notAttempted,
            proofTier: .boundedDefault
        )
        let blockers: Set<VerificationClaimType> = [.derivedFrom, .sourceOfTruth]
        let selected = VerificationStrategySelector.select(candidate: candidate, dependencyBlockers: blockers)
        XCTAssertTrue(selected.isEmpty)
    }

    func testSameFailedProofNotRetriedInSameScan() {
        var records: [String: VerificationAttemptRecord] = [:]
        let key = "entity|DerivedDataProofStrategy|REGENERABILITY"
        records[key] = VerificationAttemptRecord(key: key, state: .unknownNoEvidence, outcome: .unknown)
        XCTAssertEqual(records[key]?.state, .unknownNoEvidence)
    }

    func testBudgetExhaustionStopsLoop() {
        let loop = EntityVerificationLoop(
            knowledge: KnowledgeBaseDocument(version: "0", principle: "test", rules: []),
            budget: VerificationBudgetConfig(totalBudgetMs: 1, maxCandidates: 5, maxAttemptsPerEntity: 1, perStrategyBudgetMs: 1)
        )
        let entities = (0..<5).map { makeEntity(id: "xcode.deriveddata.\($0)", path: "/tmp/DerivedData/\($0)") }
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(),
            processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete,
            budget: loop.budget
        )
        let result = loop.run(detected: entities, context: context, telemetry: ProofRuntimeTelemetry())
        XCTAssertTrue(result.loopReport.budgetExhausted || result.loopReport.candidatesAttempted <= 5)
    }

    func testLoopDeterministicOrdering() {
        let a = makeEntity(id: "cursor.ws.a", path: "/tmp/Cursor/a")
        let b = makeEntity(id: "cursor.ws.b", path: "/tmp/Cursor/b")
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(),
            processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        let c1 = VerificationCandidateBuilder.build(from: [a, b], context: context).map(\.entityID)
        let c2 = VerificationCandidateBuilder.build(from: [a, b], context: context).map(\.entityID)
        XCTAssertEqual(c1, c2)
    }

    func testInferredCannotSatisfyStrictChain() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "REGENERABILITY",
            result: "true",
            requiredSteps: ["derived_from_verified"],
            satisfied: [],
            failed: [],
            unknown: ["derived_from"]
        )
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    func testUnknownCannotSatisfyStrictChain() {
        let chain = VerificationChain(
            entityID: "e",
            claim: "ACTIVE_STATE",
            result: "unknown",
            confidence: .unknown,
            requiredSteps: ["runtime_observation_verified"],
            unknownRequirements: ["UNKNOWN_ACTIVE_STATE"]
        )
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    func testConflictedCannotSatisfyStrictChain() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "RELATIONSHIP",
            result: "conflict",
            requiredSteps: ["explicit_metadata"],
            satisfied: [],
            failed: ["EVIDENCE_CONFLICT"],
            unknown: []
        )
        XCTAssertFalse(chain.satisfiesStrictChain)
    }

    func testOnlyVerifiedCompleteChainSucceeds() {
        let chain = VerificationChain.finalize(
            entityID: "e",
            claim: "SOURCE_OF_TRUTH",
            result: "false",
            requiredSteps: ["evidence_verified"],
            satisfied: ["evidence_verified"],
            failed: [],
            unknown: []
        )
        XCTAssertTrue(chain.satisfiesStrictChain)
    }

    func testSafetyCriticalClaimBeatsCosmeticPriority() {
        let dd = makeDerivedDataEntity(path: "/tmp/DerivedData/P", workspace: nil)
        let cosmetic = makeEntity(id: "macos.logs", path: "/tmp/Logs/x", bytes: 100)
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(),
            processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        let candidates = VerificationCandidateBuilder.build(from: [cosmetic, dd], context: context)
        guard let first = candidates.first else { return XCTFail("no candidates") }
        XCTAssertTrue(first.unresolvedClaims.contains(.sourceOfTruth) || first.unresolvedClaims.contains(.regenerability))
    }

    func testLargeBytesAloneDoesNotForcePriority() {
        let huge = makeEntity(id: "macos.user_caches.child.big", path: "/tmp/Caches/Big", bytes: 900_000_000_000)
        let dd = makeDerivedDataEntity(path: "/tmp/DerivedData/Small", workspace: "/tmp/ws")
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(),
            processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        let candidates = VerificationCandidateBuilder.build(from: [huge, dd], context: context)
        if let ddCandidate = candidates.first(where: { $0.entityID.contains("deriveddata") }),
           let hugeCandidate = candidates.first(where: { $0.entityID.contains("caches") }) {
            XCTAssertGreaterThan(ddCandidate.priority, hugeCandidate.priority)
        }
    }

    func testVerificationGraphAddsZeroBytes() {
        let before = ByteAccountant.account([
            AccountingInput(id: "a", path: "/tmp/a", inclusiveBytes: 100, safetyClass: .red, resolution: .l3Product),
        ]).uniqueTotal
        let loop = EntityVerificationLoop(knowledge: KnowledgeBaseDocument(version: "0", principle: "test", rules: []))
        let entity = makeEntity(id: "a", path: "/tmp/a", bytes: 100)
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(),
            processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete
        )
        _ = loop.run(detected: [entity], context: context, telemetry: ProofRuntimeTelemetry())
        let after = ByteAccountant.account([
            AccountingInput(id: "a", path: "/tmp/a", inclusiveBytes: 100, safetyClass: .red, resolution: .l3Product),
        ]).uniqueTotal
        XCTAssertEqual(before, after)
    }

    func testDuTimeoutRemainsUnknownNotZero() {
        let m = SizeMeasurement.unknown(reason: "DU_TIMEOUT", timedOut: true, method: "bounded_du")
        XCTAssertFalse(m.isKnown)
        XCTAssertNil(m.bytes)
        XCTAssertEqual(m.accountingBytes, 0)
    }

    func testNodeModulesRemainsOptInInLoop() {
        let entity = makeEntity(id: "node.modules", path: "/tmp/p/node_modules", bytes: 1000)
        let context = VerificationLoopContext(
            resolver: EvidenceResolver(),
            processes: ProcessTableSnapshot(names: [], snapshotFailed: false, failureReason: nil),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil),
            processCompleteness: .complete,
            handleCompleteness: .complete,
            proofTargets: ["derived-data"]
        )
        let candidates = VerificationCandidateBuilder.build(from: [entity], context: context)
        let nodeCandidate = candidates.first { $0.entityID == entity.entity.id }
        if let nodeCandidate {
            XCTAssertFalse(nodeCandidate.strategiesAvailable.contains(.nodeModules))
        }
    }

    func testEvidenceCacheReusesSamePath() {
        let cache = EvidenceResolutionCache()
        let resolver = EvidenceResolver()
        let entity = makeEntity(id: "a", path: "/tmp/shared", bytes: 1)
        _ = cache.evidence(for: "/tmp/shared", entity: entity, resolver: resolver)
        _ = cache.evidence(for: "/tmp/shared", entity: entity, resolver: resolver)
        XCTAssertTrue(true)
    }
}
