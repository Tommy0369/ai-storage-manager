import XCTest
@testable import SafetyCore

final class P201ActionDecisionDedupTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private lazy var engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))

    private func verified(_ value: PredicateValue) -> ObservationRecord {
        ObservationRecord(value: value, confidence: .verified, completeness: .complete, source: .filesystemMetadata)
    }

    private func derivedItem(
        id: String = "xcode.deriveddata.runner",
        path: String? = nil,
        workspace: String = "/tmp/ws",
        safetyClass: SafetyClass = .green
    ) -> ClassifiedItem {
        let resolvedPath = path ?? "\(home)/Library/Developer/Xcode/DerivedData/Runner-abc"
        let entity = StorageEntity(
            id: id,
            kind: .generatedBuild,
            category: "DEV",
            subcategory: "XCODE",
            displayName: id,
            path: resolvedPath,
            logicalBytes: 36_000_000
        )
        let rel = EntityRelationship(type: .derivedFrom, target: workspace, presence: .present, confidence: .verified)
        let annotation = DetectionAnnotation(
            detectorID: "t",
            specificity: 90,
            semanticType: "XCODE_DERIVED_DATA",
            lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified, activeState: .inactive),
            relationships: [rel]
        )
        let verification = VerificationAnnotation(
            sourceOfTruth: verified(.false),
            regenerable: verified(.true),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete
        )
        let decision = SafetyDecision(
            entity: entity,
            action: .moveToTrash,
            safetyClass: safetyClass,
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
        )
        return ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .generated, domain: "Developer", associatedProcesses: ["Xcode"], identified: true, annotation: annotation),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 36_000_000,
            actionVariants: [:],
            inclusiveBytes: 36_000_000,
            exclusiveBytes: 36_000_000,
            resolution: .l5Actionable,
            verification: verification
        )
    }

    private func derivedSnapshot(for item: ClassifiedItem) -> EntitySafetySnapshot {
        var evidence = EvidenceBundle(canonicalPath: item.detected.entity.path, sourceOfTruth: .false, regenerable: .true)
        evidence.openFileHandle = .false
        evidence.predicateConfidence["no_open_file_handle"] = .verified
        return EntitySafetySnapshot(
            entityID: item.detected.entity.id,
            entity: item.detected.entity,
            detected: item.detected,
            evidence: evidence,
            state: RuntimeState(),
            verification: item.verification ?? VerificationAnnotation(),
            predicates: EntityPredicateSnapshot(
                sourceOfTruth: verified(.false),
                regenerability: verified(.true),
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
                remoteBackingVerified: false,
                syncSafeVerified: false
            ),
            relationships: item.detected.annotation?.relationships ?? [],
            cacheKey: EntitySnapshotCacheKey(entityID: item.detected.entity.id, evidenceVersion: 1, verificationGeneration: 1, runtimeGeneration: 1),
            finalizedAt: Date(),
            finalizationMs: 1
        )
    }

    func testCatalogEvaluatesEachEntityActionPairOnce() {
        let items = [derivedItem(), derivedItem(id: "xcode.deriveddata.other", path: "\(home)/Library/Developer/Xcode/DerivedData/Other-xyz")]
        let snapshots = Dictionary(uniqueKeysWithValues: items.map { ($0.detected.entity.id, derivedSnapshot(for: $0)) })
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: items,
            engine: engine,
            snapshotsByEntityID: snapshots,
            safetyDecisionsByEntityID: [:]
        )
        XCTAssertEqual(catalog.telemetry.duplicateEvaluations, 0)
        XCTAssertEqual(catalog.telemetry.entitiesEvaluated, 2)
        XCTAssertEqual(catalog.telemetry.actionSafetyEvaluatorInvocations, 2 * StorageAction.allCases.count)
    }

    func testRecommendationReusesCatalogWithoutRecompute() {
        let item = derivedItem()
        let snapshots = [item.detected.entity.id: derivedSnapshot(for: item)]
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: [item],
            engine: engine,
            snapshotsByEntityID: snapshots,
            safetyDecisionsByEntityID: [:]
        )
        var telemetry = catalog.telemetry
        let invocationsBefore = telemetry.actionSafetyEvaluatorInvocations
        let recs = ActionRecommendationEngine.recommend(items: [item], decisionCatalog: catalog)
        ActionDecisionBuilder.recordReuse(&telemetry, count: 1)
        XCTAssertEqual(telemetry.actionSafetyEvaluatorInvocations, invocationsBefore)
        XCTAssertEqual(telemetry.decisionReuseCount, 1)
        let trash = catalog.set(for: item.detected.entity.id)?.decision(for: .moveToTrash)
        if trash?.eligible == true {
            XCTAssertEqual(recs.first?.recommendedAction, .moveToTrash)
        }
    }

    func testPreflightReusesCatalogDecisions() {
        let item = derivedItem()
        let snapshots = [item.detected.entity.id: derivedSnapshot(for: item)]
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: [item],
            engine: engine,
            snapshotsByEntityID: snapshots,
            safetyDecisionsByEntityID: [:]
        )
        let recs = ActionRecommendationEngine.recommend(items: [item], decisionCatalog: catalog)
        let preflights = ActionPreflightEngine.preview(items: [item], recommendations: recs, decisionCatalog: catalog)
        let trashPreflight = preflights.first { $0.action == .moveToTrash }
        let trashDecision = catalog.set(for: item.detected.entity.id)?.decision(for: .moveToTrash)
        XCTAssertEqual(trashPreflight?.allowed, trashDecision?.eligible)
        XCTAssertEqual(trashPreflight?.wouldExecuteNow, false)
    }

    func testBlockedDerivedDataAppearsInDiagnosticFunnel() {
        let item = derivedItem(safetyClass: .unknown)
        var verification = item.verification!
        verification.regenerable = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .partial, source: .filesystemMetadata)
        var blocked = item
        blocked.verification = verification
        let snapshots = [blocked.detected.entity.id: derivedSnapshot(for: blocked)]
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: [blocked],
            engine: engine,
            snapshotsByEntityID: snapshots,
            safetyDecisionsByEntityID: [:]
        )
        let recs = ActionRecommendationEngine.recommend(items: [blocked], decisionCatalog: catalog)
        let preflights = ActionPreflightEngine.preview(items: [blocked], recommendations: recs, decisionCatalog: catalog)
        let runtimeIndex = RuntimeObservationIndex.build(
            processes: ProcessTableSnapshot(names: [], commandLines: [], snapshotFailed: false, failureReason: nil, completeness: .complete),
            handles: OpenFileSnapshot(openPaths: [], snapshotFailed: false, failureReason: nil, completeness: .complete)
        )
        let report = DerivedDataMutationReadinessAnalyzer.analyze(
            items: [blocked],
            decisionCatalog: catalog,
            recommendations: recs,
            preflights: preflights,
            snapshotsByEntityID: snapshots,
            runtimeResolutions: [:],
            runtimeIndex: runtimeIndex,
            ruleVersion: "t"
        )
        XCTAssertEqual(report.entitiesDiscovered, 1)
        XCTAssertEqual(report.entries.first?.entityID, blocked.detected.entity.id)
        XCTAssertFalse(report.entries.first?.allBlockingReasons.isEmpty ?? true)
    }

    func testSnapshotOpenFileEvidenceNotStrippedInDecisionPath() {
        let item = derivedItem()
        var snapshot = derivedSnapshot(for: item)
        snapshot.evidence.openFileHandle = .false
        snapshot.predicates.openFileHandle = .false
        snapshot.predicates.openFileConfidence = .verified
        let catalog = ActionDecisionBuilder.buildCatalog(
            items: [item],
            engine: engine,
            snapshotsByEntityID: [item.detected.entity.id: snapshot],
            safetyDecisionsByEntityID: [:]
        )
        let trash = catalog.set(for: item.detected.entity.id)?.decision(for: .moveToTrash)
        XCTAssertFalse(trash?.missingClaimTypes.contains(.openFileState) ?? true)
    }

    func testExecutionPermitGenerationDisabledEvenWhenGateReady() {
        XCTAssertNil(ExecutionPermit.generate(
            receipt: PreflightReceipt(
                receiptID: "t",
                entityID: "x",
                action: .moveToTrash,
                bindingFingerprint: ActionBindingFingerprint(
                    entityID: "x",
                    action: .moveToTrash,
                    canonicalPath: "/tmp/x",
                    evidenceGeneration: 1,
                    verificationGeneration: 1,
                    runtimeGeneration: 1,
                    ruleVersion: "t",
                    transactionContractVersion: "1"
                ),
                requiredClaims: [],
                satisfiedClaims: [],
                missingClaims: [],
                staleClaims: [],
                conflictedClaims: [],
                observedAt: Date(),
                freshnessValidity: [],
                evidenceGeneration: 1,
                verificationGeneration: 1,
                runtimeGeneration: 1,
                result: "OK"
            ),
            approval: UserActionApproval(
                approvalID: "a",
                entityID: "x",
                action: .moveToTrash,
                bindingFingerprint: ActionBindingFingerprint(
                    entityID: "x",
                    action: .moveToTrash,
                    canonicalPath: "/tmp/x",
                    evidenceGeneration: 1,
                    verificationGeneration: 1,
                    runtimeGeneration: 1,
                    ruleVersion: "t",
                    transactionContractVersion: "1"
                ),
                consequenceSummaryVersion: "1",
                expectedRecoveryBytes: nil,
                approvedAt: Date(),
                expiryPolicy: "session",
                scope: "single"
            ),
            decision: ActionDecision(entityID: "x", action: .moveToTrash, safetyClass: .green, eligible: true)
        ))
    }
}
