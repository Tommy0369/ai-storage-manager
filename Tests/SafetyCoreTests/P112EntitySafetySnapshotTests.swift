import XCTest
@testable import SafetyCore

final class P112EntitySafetySnapshotTests: XCTestCase {
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
            ]
        )
    }

    private func derivedEntity(path: String) -> DetectedEntity {
        DetectedEntity(
            entity: StorageEntity(
                id: "xcode.deriveddata.test",
                kind: .generatedBuild,
                category: "DEV",
                subcategory: "XCODE",
                displayName: "DerivedData",
                path: path,
                logicalBytes: 36_000_000
            ),
            bucket: .generated,
            domain: "Developer",
            associatedProcesses: [],
            identified: true,
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 90,
                semanticType: "XCODE_DERIVED_DATA",
                lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified, activeState: .inactive),
                relationships: [
                    EntityRelationship(
                        type: .derivedFrom,
                        target: "/tmp/project.xcodeproj",
                        presence: .present,
                        confidence: .verified
                    ),
                ]
            )
        )
    }

    private struct FixedHandle: OpenHandleChecker {
        let value: PredicateValue
        func hasOpenHandles(path: String) -> PredicateValue { value }
    }

    private func loopContext() -> VerificationLoopContext {
        let handles = FixedHandle(value: .false)
        return VerificationLoopContext(
            resolver: EvidenceResolver(processes: ProcessCheck(), handles: handles),
            processes: ProcessCheck(),
            handles: handles,
            processCompleteness: .complete,
            handleCompleteness: .complete,
            proofTargets: ["derived-data"]
        )
    }

    func testSnapshotCreatedOncePerEntityPerSession() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let cache = EvidenceResolutionCache()
        let context = loopContext()
        let path = "/Users/me/Library/Developer/Xcode/DerivedData/App-abc"
        var entity = derivedEntity(path: path)
        var evidence = EvidenceBundle(canonicalPath: path, sourceOfTruth: .false, regenerable: .true)
        evidence.openFileHandle = .false
        evidence.predicateConfidence["no_open_file_handle"] = .verified
        var verification = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            provenanceConfidence: .verified
        )

        let snapshot1 = session.finalizeSnapshot(entity: &entity, evidence: &evidence, verification: &verification, context: context, cache: cache)

        var entity2 = derivedEntity(path: path)
        var evidence2 = EvidenceBundle(canonicalPath: path, sourceOfTruth: .false, regenerable: .true)
        evidence2.openFileHandle = .false
        evidence2.predicateConfidence["no_open_file_handle"] = .verified
        var verification2 = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            provenanceConfidence: .verified
        )
        let snapshot2 = session.finalizeSnapshot(entity: &entity2, evidence: &evidence2, verification: &verification2, context: context, cache: cache)

        let resolver = session.resolverRuntimeReport()
        let sot = resolver.resolvers.first { $0.resolver == "source_of_truth" }
        XCTAssertEqual(sot?.cacheMisses, 0)
        XCTAssertEqual(sot?.cacheHits, 1)
        XCTAssertEqual(session.entitySnapshotRuntimeReport().snapshotsCreated, 1)
        XCTAssertEqual(session.entitySnapshotRuntimeReport().snapshotCacheHits, 1)
        XCTAssertEqual(snapshot1.entityID, snapshot2.entityID)
    }

    func testVerifiedClaimsSkipResolverMisses() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let cache = EvidenceResolutionCache()
        let context = loopContext()
        let path = "/Users/me/Library/Developer/Xcode/DerivedData/App-abc"
        var entity = derivedEntity(path: path)
        var evidence = EvidenceBundle(canonicalPath: path)
        var verification = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete
        )
        _ = session.finalizeSnapshot(entity: &entity, evidence: &evidence, verification: &verification, context: context, cache: cache)
        let report = session.resolverRuntimeReport()
        XCTAssertTrue(report.resolvers.allSatisfy { $0.cacheMisses == 0 })
        XCTAssertEqual(report.resolvers.first { $0.resolver == "source_of_truth" }?.cacheHits, 1)
        XCTAssertEqual(report.resolvers.first { $0.resolver == "regenerability" }?.cacheHits, 1)
        XCTAssertEqual(report.resolvers.first { $0.resolver == "active_state" }?.cacheHits, 1)
    }

    func testEvaluateActionsReusesSnapshot() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let cache = EvidenceResolutionCache()
        let context = loopContext()
        let path = "/Users/me/Library/Developer/Xcode/DerivedData/App-abc"
        var entity = derivedEntity(path: path)
        var evidence = EvidenceBundle(canonicalPath: path, sourceOfTruth: .false, regenerable: .true)
        evidence.openFileHandle = .false
        evidence.predicateConfidence["not_source_of_truth"] = .verified
        evidence.predicateConfidence["regenerable"] = .verified
        evidence.predicateConfidence["no_open_file_handle"] = .verified
        var verification = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete
        )
        let snapshot = session.finalizeSnapshot(
            entity: &entity,
            evidence: &evidence,
            verification: &verification,
            context: context,
            cache: cache
        )
        let batch = session.evaluateActions(snapshot: snapshot, includeCloudVariants: true)
        XCTAssertEqual(batch.primary.safetyClass, .green)
        XCTAssertEqual(batch.actionsEvaluated, 3)
        XCTAssertGreaterThan(session.actionEvalRuntimeReport().snapshotReuseCount, 0)
    }

    func testTriStatePreservedThroughSnapshot() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let cache = EvidenceResolutionCache()
        let context = loopContext()
        let path = "/Users/me/Library/Caches/unknown-artifact"
        var entity = DetectedEntity(
            entity: StorageEntity(id: "cache.unknown", kind: .cache, category: "t", subcategory: "t", displayName: "c", path: path, logicalBytes: 1),
            bucket: .userData,
            domain: "Cache",
            associatedProcesses: [],
            identified: true,
            annotation: nil
        )
        var evidence = EvidenceBundle(canonicalPath: path)
        var verification = VerificationAnnotation()
        let snapshot = session.finalizeSnapshot(
            entity: &entity,
            evidence: &evidence,
            verification: &verification,
            context: context,
            cache: cache
        )
        XCTAssertEqual(snapshot.predicates.sourceOfTruth.confidence, .unknown)
        XCTAssertEqual(snapshot.predicates.regenerability.confidence, .unknown)
        XCTAssertNotEqual(snapshot.predicates.sourceOfTruth.value, .true)
    }

    func testMoveToTrashSOTDoesNotLeakIntoICloud() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (home as NSString).appendingPathComponent("Documents/user-file.txt")
        let item = ClassifiedItem(
            detected: DetectedEntity(
                entity: StorageEntity(id: "user.doc", kind: .userOriginal, category: "t", subcategory: "t", displayName: "doc", path: path, logicalBytes: 1),
                bucket: .userData,
                domain: "User",
                associatedProcesses: [],
                identified: true,
                annotation: DetectionAnnotation(
                    detectorID: "test",
                    specificity: 80,
                    semanticType: "USER_DOC",
                    lifecycle: LifecycleEvidence(role: .userContent, roleConfidence: .verified, activeState: .inactive)
                )
            ),
            decision: SafetyDecision(
                entity: StorageEntity(id: "user.doc", kind: .userOriginal, category: "t", subcategory: "t", displayName: "doc", path: path, logicalBytes: 1),
                action: .userReview,
                safetyClass: .yellow,
                safetyScore: nil,
                reasonCodes: [],
                sideEffects: [],
                matchedRuleID: nil,
                evaluationLayer: .unknownFallback,
                evidenceConfidence: 0.8,
                userExplanationJA: "t",
                growthCauses: [],
                requiresUserApproval: true,
                blockedBy: nil
            ),
            semantic: SemanticResult(from: SafetyDecision(
                entity: StorageEntity(id: "user.doc", kind: .userOriginal, category: "t", subcategory: "t", displayName: "doc", path: path, logicalBytes: 1),
                action: .userReview,
                safetyClass: .yellow,
                safetyScore: nil,
                reasonCodes: [],
                sideEffects: [],
                matchedRuleID: nil,
                evaluationLayer: .unknownFallback,
                evidenceConfidence: 0.8,
                userExplanationJA: "t",
                growthCauses: [],
                requiresUserApproval: true,
                blockedBy: nil
            )),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l4SemanticEntity,
            verification: VerificationAnnotation(
                sourceOfTruth: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                regenerable: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
                activeState: .inactive,
                activeStateConfidence: .verified,
                activeStateCompleteness: .complete
            )
        )
        let engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))
        var evidence = EvidenceBundle(canonicalPath: path)
        evidence.openFileHandle = .false
        let trash = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: evidence,
            state: RuntimeState(),
            userContext: ActionUserContext.default
        )
        let iCloud = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: evidence,
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        )
        XCTAssertFalse(trash.eligible)
        XCTAssertTrue(trash.blockedReasons.contains(.sourceOfTruthUnknown) || trash.blockedReasons.contains(.safetyClassRed))
        XCTAssertTrue(iCloud.explanationCodes.contains("SOT_TRUE_ALLOWED") || iCloud.satisfiedClaimTypes.contains(.preservationContract))
    }

    func testDerivedDataOpenFileVerifiedSafeUsesSnapshotEvidence() {
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer/Xcode/DerivedData/App-xyz"
        let entity = derivedEntity(path: path)
        var evidence = EvidenceBundle(canonicalPath: path, sourceOfTruth: .false, regenerable: .true)
        evidence.openFileHandle = .false
        evidence.predicateConfidence["no_open_file_handle"] = .verified
        let verification = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete
        )
        let snapshot = EntitySafetySnapshot(
            entityID: entity.entity.id,
            entity: entity.entity,
            detected: entity,
            evidence: evidence,
            state: RuntimeState(),
            verification: verification,
            predicates: EntityPredicateSnapshot(
                sourceOfTruth: verification.sourceOfTruth,
                regenerability: verification.regenerable,
                activeState: .inactive,
                activeStateConfidence: .verified,
                openFileHandle: .false,
                openFileConfidence: .verified,
                isGitRepository: false,
                isApplicationManaged: true,
                isDerivedData: true,
                isUserOwnedVerified: false,
                hasEvidenceConflict: false,
                hasCanonicalPath: true,
                isSymlinkAmbiguity: false,
                isUserOriginal: false,
                isGeneratedArtifact: true,
                isInsideProtectedRoot: false,
                fileProviderBacked: false,
                remoteBackingVerified: true,
                syncSafeVerified: false
            ),
            relationships: entity.annotation?.relationships ?? [],
            cacheKey: EntitySnapshotCacheKey(entityID: entity.entity.id, evidenceVersion: evidence.snapshotVersion, verificationGeneration: verification.snapshotGeneration, runtimeGeneration: 1),
            finalizedAt: Date(),
            finalizationMs: 1
        )
        let item = ClassifiedItem(
            detected: entity,
            decision: SafetyDecision(
                entity: entity.entity,
                action: .moveToTrash,
                safetyClass: .green,
                safetyScore: SafetyScore(value: 95),
                reasonCodes: ["GENERATED_DATA"],
                sideEffects: [],
                matchedRuleID: "test.derived",
                evaluationLayer: .exactVendor,
                evidenceConfidence: 0.95,
                userExplanationJA: "DerivedData",
                growthCauses: [],
                requiresUserApproval: true,
                blockedBy: nil
            ),
            semantic: SemanticResult(from: SafetyDecision(
                entity: entity.entity,
                action: .moveToTrash,
                safetyClass: .green,
                safetyScore: SafetyScore(value: 95),
                reasonCodes: ["GENERATED_DATA"],
                sideEffects: [],
                matchedRuleID: "test.derived",
                evaluationLayer: .exactVendor,
                evidenceConfidence: 0.95,
                userExplanationJA: "DerivedData",
                growthCauses: [],
                requiresUserApproval: true,
                blockedBy: nil
            )),
            allocatedBytes: 36_000_000,
            actionVariants: [:],
            inclusiveBytes: 36_000_000,
            exclusiveBytes: 36_000_000,
            resolution: .l5Actionable,
            verification: verification
        )
        let engine = SafetyRuleEngine(knowledge: sampleKnowledge())
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path),
            state: RuntimeState(),
            snapshot: snapshot,
            safetyDecisions: [.moveToTrash: item.decision]
        )
        XCTAssertTrue(decision.eligible)
        XCTAssertFalse(decision.blockedReasons.contains(ActionBlockReason.verificationIncomplete))
    }

    func testRuntimeGenerationChangeInvalidatesSnapshotCache() {
        var session = SafetyEvalSession(knowledge: sampleKnowledge())
        let cache = EvidenceResolutionCache()
        var context = loopContext()
        let path = "/Users/me/Library/Developer/Xcode/DerivedData/App-abc"
        var entity = derivedEntity(path: path)
        var evidence = EvidenceBundle(canonicalPath: path)
        var verification = VerificationAnnotation(
            sourceOfTruth: ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            regenerable: ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .filesystemMetadata),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete
        )
        _ = session.finalizeSnapshot(entity: &entity, evidence: &evidence, verification: &verification, context: context, cache: cache)
        context = VerificationLoopContext(
            resolver: context.resolver,
            processes: context.processes,
            handles: context.handles,
            processCompleteness: .partial,
            handleCompleteness: context.handleCompleteness,
            proofTargets: context.proofTargets
        )
        _ = session.finalizeSnapshot(entity: &entity, evidence: &evidence, verification: &verification, context: context, cache: cache)
        XCTAssertEqual(session.entitySnapshotRuntimeReport().snapshotsCreated, 2)
        XCTAssertEqual(session.entitySnapshotRuntimeReport().snapshotCacheHits, 0)
    }
}
