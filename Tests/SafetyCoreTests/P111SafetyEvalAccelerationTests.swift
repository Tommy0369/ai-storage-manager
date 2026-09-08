import XCTest
@testable import SafetyCore

final class P111SafetyEvalAccelerationTests: XCTestCase {
    private func sampleKnowledge() -> KnowledgeBaseDocument {
        KnowledgeBaseDocument(
            version: "t",
            principle: "t",
            rules: [
                SafetyRule(
                    id: "test.derived",
                    entity: "derived",
                    category: "DEV",
                    subcategory: "XCODE",
                    match: RuleMatch(path: "**/DerivedData/**"),
                    defaultClass: .green,
                    baseScore: 95,
                    evaluationLayer: .exactVendor,
                    sourceOfTruth: false,
                    regenerable: true,
                    networkRequired: false,
                    requiredPredicates: ["not_source_of_truth", "regenerable", "no_open_file_handle"],
                    demoteToYellowIf: [],
                    demoteToRedIf: [],
                    hardBlockIf: [],
                    actionMode: .moveToTrash,
                    effects: [],
                    verification: [],
                    growthCauses: [],
                    explanationJA: "DerivedData",
                    reasonCodes: ["GENERATED_DATA"]
                ),
                SafetyRule(
                    id: "test.generic",
                    entity: "generic",
                    category: "GENERIC",
                    subcategory: "CACHE",
                    match: RuleMatch(path: "**/Library/Caches/**"),
                    defaultClass: .yellow,
                    baseScore: 50,
                    evaluationLayer: .genericCacheTemp,
                    sourceOfTruth: false,
                    regenerable: true,
                    networkRequired: false,
                    requiredPredicates: [],
                    demoteToYellowIf: [],
                    demoteToRedIf: [],
                    hardBlockIf: [],
                    actionMode: .moveToTrash,
                    effects: [],
                    verification: [],
                    growthCauses: [],
                    explanationJA: "Cache",
                    reasonCodes: ["CACHE"]
                ),
            ]
        )
    }

    private func evidence(path: String, sot: PredicateValue = .false, regen: PredicateValue = .true) -> EvidenceBundle {
        var e = EvidenceBundle(canonicalPath: path, isSymlink: .false, sourceOfTruth: sot, regenerable: regen)
        e.openFileHandle = .false
        e.owningProcessRunning = .false
        e.predicateConfidence["not_source_of_truth"] = .verified
        e.predicateConfidence["regenerable"] = .verified
        e.predicateConfidence["no_open_file_handle"] = .verified
        return e
    }

    func testIndexedRuleLookupMatchesReference() {
        let knowledge = sampleKnowledge()
        var index = SafetyRuleIndex(knowledge: knowledge)
        let engine = SafetyRuleEngine(knowledge: knowledge)
        let paths = [
            "/Users/me/Library/Developer/Xcode/DerivedData/App-abc",
            "/Users/me/Library/Caches/foo",
            "/Users/me/Documents/file.txt",
        ]
        for path in paths {
            let indexed = index.matchingRules(for: path)
            let reference = engine.evaluateReference(EvaluationRequest(
                entity: StorageEntity(id: "x", kind: .generatedBuild, category: "t", subcategory: "t", displayName: "x", path: path, logicalBytes: 1),
                intendedAction: .userReview,
                evidence: evidence(path: path),
                state: RuntimeState()
            ))
            let pick = SafetyRuleEngine.selectRule(indexed, loader: KnowledgeBaseLoader())
            XCTAssertEqual(pick?.id, reference.matchedRuleID, path)
        }
    }

    func testHardBlockStillWinsOverIndexedRules() {
        let engine = SafetyRuleEngine(knowledge: sampleKnowledge())
        let decision = engine.evaluate(EvaluationRequest(
            entity: StorageEntity(id: "sys", kind: .systemProtected, category: "t", subcategory: "t", displayName: "sys", path: "/System/Library/foo", logicalBytes: 1),
            intendedAction: .moveToTrash,
            evidence: EvidenceBundle(canonicalPath: "/System/Library/foo"),
            state: RuntimeState()
        ))
        XCTAssertEqual(decision.safetyClass, .red)
        XCTAssertEqual(decision.action, .hardBlock)
    }

    func testGreenAuditorSkippedForNonGreen() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let entity = StorageEntity(id: "x", kind: .cache, category: "t", subcategory: "t", displayName: "x", path: "/Users/me/Library/Caches/x", logicalBytes: 1)
        let decision = SafetyDecision(
            entity: entity,
            action: .userReview,
            safetyClass: .unknown,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0.5,
            userExplanationJA: "t",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        let item = ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .generated, domain: "t", associatedProcesses: [], identified: true, annotation: nil),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l2Domain,
            verification: nil
        )
        let (_, record) = session.audit(item: item, evidence: evidence(path: entity.path), state: RuntimeState())
        XCTAssertNil(record)
        XCTAssertEqual(session.greenAuditorRuntime().skippedNonGreen, 1)
        XCTAssertEqual(session.greenAuditorRuntime().fullAudits, 0)
    }

    func testGreenAuditorRunsForGreen() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let path = "/Users/me/Library/Developer/Xcode/DerivedData/App-xyz"
        let entity = StorageEntity(id: "dd", kind: .generatedBuild, category: "t", subcategory: "t", displayName: "dd", path: path, logicalBytes: 1)
        let decision = session.evaluate(EvaluationRequest(
            entity: entity,
            intendedAction: .userReview,
            evidence: evidence(path: path),
            state: RuntimeState()
        ))
        XCTAssertEqual(decision.safetyClass, .green)
        let item = ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .generated, domain: "t", associatedProcesses: [], identified: true, annotation: nil),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l4SemanticEntity,
            verification: VerificationAnnotation(
                sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                activeState: .inactive,
                activeStateConfidence: .verified,
                activeStateCompleteness: .complete,
                provenanceConfidence: .verified
            )
        )
        let (_, record) = session.audit(item: item, evidence: evidence(path: path), state: RuntimeState())
        XCTAssertNotNil(record)
        XCTAssertEqual(session.greenAuditorRuntime().fullAudits, 1)
    }

    func testCursorExplicitRouteNotFoundBlocksDefaultProof() {
        let entity = DetectedEntity(
            entity: StorageEntity(id: "cursor.snapshots.store", kind: .cache, category: "t", subcategory: "t", displayName: "s", path: "/Users/me/Library/Application Support/Cursor/snapshots/stores/foo", logicalBytes: 1),
            bucket: .developer,
            domain: "AI Tools",
            associatedProcesses: [],
            identified: true,
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 50,
                semanticType: "CURSOR_SNAPSHOT",
                lifecycle: LifecycleEvidence(role: .snapshot, roleConfidence: .inferred)
            )
        )
        let assessment = ProofFeasibilityResolver.assess(entity: entity, strategy: .cursorMetadata)
        XCTAssertEqual(assessment.feasibility, .explicitRouteNotFound)
        XCTAssertEqual(assessment.reason, "NO_EXPLICIT_METADATA_ROUTE")
    }

    func testGitRepositoryBlockedFromMoveToICloudRecommendation() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (home as NSString).appendingPathComponent("Documents/project/.git")
        let entity = StorageEntity(id: "git.dot_git", kind: .gitMetadata, category: "t", subcategory: "t", displayName: "git", path: path, logicalBytes: 1)
        let decision = SafetyDecision(
            entity: entity,
            action: .userReview,
            safetyClass: .red,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0.5,
            userExplanationJA: "t",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        let item = ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .userData, domain: "Git", associatedProcesses: [], identified: true, annotation: nil),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l4SemanticEntity,
            verification: nil
        )
        let engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))
        let iCloud = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path),
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        )
        XCTAssertFalse(iCloud.eligible)
        XCTAssertTrue(iCloud.blockedReasons.contains(.relocationContractMissing))
        let rec = ActionRecommendationEngine.recommend(items: [item], engine: engine).first!
        XCTAssertEqual(rec.recommendedAction, .keep)
    }

    func testSafetyResultCacheHitsOnIdenticalInput() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let entity = StorageEntity(id: "dd", kind: .generatedBuild, category: "t", subcategory: "t", displayName: "dd", path: "/Users/me/Library/Developer/Xcode/DerivedData/X", logicalBytes: 1)
        let req = EvaluationRequest(entity: entity, intendedAction: .userReview, evidence: evidence(path: entity.path), state: RuntimeState())
        _ = session.evaluate(req)
        _ = session.evaluate(req)
        XCTAssertEqual(session.runtimeReport(totalMs: 1, entities: 1, actions: 2).resultCacheHits, 1)
    }
}
