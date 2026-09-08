import XCTest
@testable import SafetyCore

final class P205DerivedDataStrictProofChainTests: XCTestCase {
    private func makeHome() throws -> String {
        let dir = NSTemporaryDirectory() + "asm-p205-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func installRunnerFixture(home: String, name: String, workspacePath: String) throws -> String {
        let dd = "\(home)/Library/Developer/Xcode/DerivedData/\(name)"
        try FileManager.default.createDirectory(atPath: dd, withIntermediateDirectories: true)
        let plist: [String: Any] = ["WorkspacePath": workspacePath]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: "\(dd)/info.plist"))
        return dd
    }

    private func makeItem(id: String, path: String, annotation: DetectionAnnotation?, verification: VerificationAnnotation?) -> ClassifiedItem {
        let entity = StorageEntity(id: id, kind: .generatedBuild, category: "Xcode", subcategory: "DerivedData", displayName: id, path: path, logicalBytes: 1_000_000)
        let decision = SafetyDecision(
            entity: entity,
            action: .noAction,
            safetyClass: .red,
            safetyScore: SafetyScore(value: 30),
            reasonCodes: ["SOURCE_ACTIVE"],
            sideEffects: [],
            matchedRuleID: "test",
            evaluationLayer: .exactVendor,
            evidenceConfidence: 0.9,
            userExplanationJA: "test",
            growthCauses: [],
            requiresUserApproval: false,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .developer, domain: "Xcode", associatedProcesses: ["Xcode"], identified: true, annotation: annotation),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: 1_000_000,
            actionVariants: [:],
            inclusiveBytes: 1_000_000,
            exclusiveBytes: 1_000_000,
            resolution: .l4SemanticEntity,
            verification: verification
        )
    }

    func testRootUnknownDoesNotContaminateVerifiedChild() throws {
        let home = try makeHome()
        let project = "\(home)/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let childPath = try installRunnerFixture(home: home, name: "Runner-proof", workspacePath: project)
        let rootPath = "\(home)/Library/Developer/Xcode/DerivedData"

        let childRel = EntityRelationship(type: .derivedFrom, target: project, presence: .present, confidence: .verified)
        let childAnn = DetectionAnnotation(
            detectorID: "xcode.deriveddata.proof",
            specificity: 120,
            semanticType: "XCODE_DERIVEDDATA_INSTANCE",
            lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified),
            relationships: [childRel]
        )
        let sot = ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .relationshipMetadata, reasonCode: "VERIFIED_DERIVED_ARTIFACT")
        let regen = ObservationRecord(value: .true, confidence: .verified, completeness: .complete, source: .vendorRule, reasonCode: "XCODE_DERIVEDDATA_REBUILD")
        let verification = VerificationAnnotation(
            sourceOfTruth: sot,
            regenerable: regen,
            activeState: .active,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            provenanceConfidence: .verified,
            unknownReasons: []
        )

        let rootItem = makeItem(id: "xcode.derived_data", path: rootPath, annotation: nil, verification: nil)
        let childItem = makeItem(
            id: "xcode.deriveddata.Runner-proof",
            path: childPath,
            annotation: childAnn,
            verification: verification
        )

        let trash = ActionDecision(entityID: childItem.detected.entity.id, action: .moveToTrash, safetyClass: .red, eligible: false, blockedReasons: [.sourceActive, .sourceOpen])
        let catalog = ActionDecisionCatalog(
            setsByEntityID: [
                childItem.detected.entity.id: ActionDecisionSet(
                    entityID: childItem.detected.entity.id,
                    snapshotGeneration: 1,
                    evidenceGeneration: 1,
                    runtimeGeneration: 1,
                    decisions: [.moveToTrash: trash]
                ),
            ],
            telemetry: ActionSafetyEvalDedupReport(
                actionSafetyEvaluatorInvocations: 1,
                uniqueEntityActionPairs: 1,
                duplicateEvaluations: 0,
                decisionReuseCount: 0,
                entitiesEvaluated: 1,
                buildRuntimeMs: 0
            )
        )

        let report = DerivedDataStrictProofChainAnalyzer.analyze(
            items: [rootItem, childItem],
            snapshotsByEntityID: [:],
            decisionCatalog: catalog,
            recommendations: [],
            preflights: [],
            mutationGate: MutationGateReport(entries: [], executorImplemented: false),
            readiness: DerivedDataMutationReadinessReport(
                entries: [], entitiesDiscovered: 0, moveToTrashSafetyGreen: 0,
                recommendedMoveToTrash: 0, preflightRequired: 0, approvalRequired: 0,
                contractSatisfiedReadOnly: 0, executorImplemented: false
            ),
            gate: FirstRealMutationGateReport(
                gate: "FIRST_REAL_MUTATION_GATE",
                status: "NO_SAFE_REAL_MUTATION_CANDIDATE",
                selectedCandidate: nil,
                selectedAction: nil,
                reason: [],
                selectionOutcome: FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue,
                approvalRequiredCount: 0,
                contractSatisfiedReadOnlyCount: 0,
                preflightRequiredCount: 0,
                rankingEligibleCount: 0,
                executorImplemented: false,
                previewExecutable: false,
                destructiveActionsExecuted: false,
                realDerivedDataCandidates: 0,
                approvalRequired: 0,
                contractSatisfiedReadOnly: 0,
                topBlockers: []
            )
        )

        XCTAssertEqual(report.rootDerivedDataEntities, 1)
        XCTAssertEqual(report.concreteDerivedDataEntities, 1)
        XCTAssertEqual(report.childSOTFalseVerified, 1)
        XCTAssertEqual(report.childRegenTrueVerified, 1)
        XCTAssertFalse(report.rootChildContaminationSuspected)
        XCTAssertEqual(report.contradictionClassification, ContradictionClassification.expectedAggregation.rawValue)

        let child = report.entities.first { $0.isConcreteChild }!
        XCTAssertEqual(child.workspaceRelationshipConfidence, EvidenceConfidence.verified.rawValue)
        XCTAssertEqual(child.sourceOfTruth, PredicateValue.false.rawValue)
        XCTAssertEqual(child.regenerability, PredicateValue.true.rawValue)
        XCTAssertTrue(child.causalBlockerChain.contains("SOURCE_ACTIVE") || child.causalBlockerChain.contains("RUNTIME_ACTIVE_BLOCK"))
    }

    func testVerifiedRelationshipReachesSOTResolver() throws {
        let home = try makeHome()
        let project = "\(home)/ws/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let childPath = try installRunnerFixture(home: home, name: "Runner-sot", workspacePath: project)
        let rel = EntityRelationship(type: .derivedFrom, target: project, presence: .present, confidence: .verified)
        let ann = DetectionAnnotation(
            detectorID: "t",
            specificity: 100,
            semanticType: "XCODE_DERIVEDDATA_INSTANCE",
            lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified),
            relationships: [rel]
        )
        let entity = StorageEntity(id: "xcode.deriveddata.Runner-sot", kind: .generatedBuild, category: "X", subcategory: "D", displayName: "d", path: childPath, logicalBytes: 1)
        let sot = SourceOfTruthResolver.resolve(entity: entity, annotation: ann, evidence: EvidenceBundle(canonicalPath: childPath))
        XCTAssertEqual(sot.value, .false)
        XCTAssertEqual(sot.confidence, .verified)
        let regen = RegenerabilityResolver.resolve(entity: entity, annotation: ann, evidence: EvidenceBundle(canonicalPath: childPath, sourceProjectExists: .true), sourceOfTruth: sot)
        XCTAssertEqual(regen.value, .true)
        XCTAssertEqual(regen.confidence, .verified)
    }

    func testCanonicalVerifiedNotOverwrittenByWeakerUnknown() {
        let existing = ObservationRecord(value: .false, confidence: .verified, completeness: .complete, source: .relationshipMetadata, reasonCode: "VERIFIED_DERIVED_ARTIFACT")
        let resolved = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .unknown, source: .unknown, reasonCode: UnknownReasonCode.unknownSourceOfTruth.rawValue)
        let merged = EntitySafetySnapshotBuilder.mergeClaim(existing: existing, resolved: resolved)
        XCTAssertEqual(merged.value, .false)
        XCTAssertEqual(merged.confidence, .verified)
    }

    func testRegenBlockedBySOTWhenSOTUnknown() {
        let entity = StorageEntity(id: "x", kind: .generatedBuild, category: "X", subcategory: "D", displayName: "d", path: "/tmp/DerivedData/x", logicalBytes: 1)
        let sot = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .partial, source: .unknown, reasonCode: UnknownReasonCode.unknownSourceOfTruth.rawValue)
        let regen = RegenerabilityResolver.resolve(entity: entity, annotation: nil, evidence: EvidenceBundle(canonicalPath: entity.path), sourceOfTruth: sot)
        XCTAssertEqual(regen.value, .unknown)
        XCTAssertNotEqual(regen.confidence, .verified)
    }

    func testCausalChainReportsRootBeforeDependent() {
        let requirements = [
            StrictProofRequirement(requirement: "explicit_workspace_relationship_verified", required: true, value: nil, confidence: nil, completeness: nil, evidenceSource: nil, satisfied: false, blockingReason: "MISSING_EXPLICIT_WORKSPACE_RELATIONSHIP"),
            StrictProofRequirement(requirement: "sot_false_verified", required: true, value: "unknown", confidence: "UNKNOWN", completeness: nil, evidenceSource: nil, satisfied: false, blockingReason: "SOT_PROOF_INCOMPLETE"),
            StrictProofRequirement(requirement: "regenerable_true_verified", required: true, value: "unknown", confidence: "UNKNOWN", completeness: nil, evidenceSource: nil, satisfied: false, blockingReason: "REGEN_BLOCKED_BY_SOT"),
        ]
        let chain = DerivedDataStrictProofChainAnalyzer.buildCausalChain(
            requirements: requirements,
            trashDecision: nil,
            readiness: nil,
            sot: ObservationRecord(value: .unknown, confidence: .unknown, completeness: .partial, source: .unknown, reasonCode: "x"),
            regen: ObservationRecord(value: .unknown, confidence: .unknown, completeness: .partial, source: .unknown, reasonCode: "y")
        )
        XCTAssertEqual(chain.first, "MISSING_EXPLICIT_WORKSPACE_RELATIONSHIP")
        XCTAssertTrue(chain.contains("SOT_PROOF_INCOMPLETE"))
    }

    func testRealCandidateClassifiesRuntimeNotSOTWhenProofComplete() {
        let entry = DerivedDataMutationReadinessEntry(
            entityID: "xcode.deriveddata.Test",
            canonicalPath: "/tmp/DerivedData/Test",
            measurementBytes: 1000,
            semanticIdentity: "XCODE_DERIVEDDATA_INSTANCE",
            generatedBy: "XCODE",
            derivedFrom: "/tmp/ws.xcodeproj",
            sourceWorkspace: "/tmp/ws.xcodeproj",
            sourceWorkspaceExists: true,
            sourceOfTruth: "false",
            sourceOfTruthConfidence: "verified",
            regenerability: "true",
            regenerabilityConfidence: "verified",
            activeState: "ACTIVE",
            activeStateConfidence: "VERIFIED",
            openFileState: "true",
            openFileConfidence: "verified",
            xcodeRunning: "running",
            xcodebuildRunning: "inactive",
            evidenceFreshness: "RESOLVED",
            evidenceCompleteness: "COMPLETE",
            evidenceConflicts: false,
            moveToTrashSafetyClass: "RED",
            moveToTrashEligible: false,
            matchedRuleID: "t",
            recommendation: "KEEP",
            recommendationDisposition: "keep",
            preflightAllowed: false,
            mutationReadiness: MutationReadiness.blocked.rawValue,
            firstBlockingGate: "xcode_inactive_verified",
            allBlockingReasons: ["SOURCE_ACTIVE", "SOURCE_OPEN", "SAFETY_CLASS_RED"],
            gateSteps: [],
            transactionContractAvailable: true,
            postVerifyContractAvailable: true,
            auditContractAvailable: true,
            bindingFingerprintPossible: true,
            rootCauseCategory: nil,
            executorImplemented: false
        )
        let funnelEntry = DerivedDataSurfaceFunnelEntry(
            path: "/tmp/DerivedData/Test",
            childName: "Test",
            filesystemObserved: true,
            scannerObserved: true,
            detectorCandidate: true,
            detectorMatched: true,
            entityEmitted: true,
            entityDeduplicated: false,
            entityDroppedReason: nil,
            proofCandidate: true,
            proofAttempted: true,
            proofResult: "verified",
            reportSurfaced: true,
            finalEntityID: "xcode.deriveddata.Test",
            infoPlistPresent: true,
            workspacePathPresent: true,
            workspaceExists: true,
            measurementKnown: true
        )
        let cls = RealCandidateRevalidationAnalyzer.classifyBlocker(
            funnelEntry: funnelEntry,
            readiness: entry,
            allBlockers: entry.allBlockingReasons
        )
        XCTAssertEqual(cls, .realRuntimeStateBlock)
    }
}
