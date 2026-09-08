import XCTest
@testable import SafetyCore

final class P20ActionArchitectureTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private lazy var engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))

    private func makeItem(
        id: String,
        path: String,
        bytes: Int64 = 1_000_000,
        bucket: SystemDataBucket = .userData,
        kind: EntityKind = .userOriginal,
        verification: VerificationAnnotation? = nil,
        annotation: DetectionAnnotation? = nil,
        safetyClass: SafetyClass = .yellow,
        action: ActionMode = .userReview
    ) -> ClassifiedItem {
        let entity = StorageEntity(
            id: id,
            kind: kind,
            category: "test",
            subcategory: "test",
            displayName: id,
            path: path,
            logicalBytes: bytes
        )
        let decision = SafetyDecision(
            entity: entity,
            action: action,
            safetyClass: safetyClass,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0.8,
            userExplanationJA: "test",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(
                entity: entity,
                bucket: bucket,
                domain: "test",
                associatedProcesses: [],
                identified: true,
                annotation: annotation
            ),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: bytes,
            actionVariants: [:],
            inclusiveBytes: bytes,
            exclusiveBytes: bytes,
            resolution: .l4SemanticEntity,
            verification: verification
        )
    }

    private func verified(_ value: PredicateValue) -> ObservationRecord {
        ObservationRecord(value: value, confidence: .verified, completeness: .complete, source: .filesystemMetadata)
    }

    private func userContentLifecycle() -> LifecycleEvidence {
        LifecycleEvidence(role: .userContent, roleConfidence: .verified, activeState: .inactive)
    }

    private func generatedLifecycle() -> LifecycleEvidence {
        LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified, activeState: .inactive)
    }

    private func inactiveVerification(sot: PredicateValue, regen: PredicateValue = .unknown) -> VerificationAnnotation {
        VerificationAnnotation(
            sourceOfTruth: verified(sot),
            regenerable: verified(regen),
            activeState: .inactive,
            activeStateConfidence: .verified,
            activeStateCompleteness: .complete,
            provenanceConfidence: .verified
        )
    }

    // MARK: - ActionMode migration

    func testActionModeMigrationExactMapping() {
        XCTAssertEqual(ActionArchitecture.storageAction(from: .moveToTrash), .moveToTrash)
        XCTAssertEqual(ActionArchitecture.storageAction(from: .cloudEvictOnly), .removeLocalDownload)
        XCTAssertEqual(ActionArchitecture.storageAction(from: .noAction), .keep)
        XCTAssertEqual(ActionArchitecture.storageAction(from: .userReview), .keep)
        XCTAssertEqual(ActionArchitecture.storageAction(from: .toolCLIOnly), .vendorNativeCleanup)
    }

    func testAmbiguousLegacyActionModeDoesNotGuess() {
        XCTAssertNil(ActionArchitecture.storageAction(from: .hardBlock))
        XCTAssertNil(ActionArchitecture.storageAction(from: .permanentDelete))
    }

    func testICloudTransactionPhaseIncludesLocalCopyVerified() {
        XCTAssertEqual(ICloudTransactionPhase.localCopyVerified.rawValue, "LOCAL_COPY_VERIFIED")
    }

    // MARK: - MOVE_TO_ICLOUD vs SOT

    func testSOTTrueUserVideoEligibleForMoveToICloud() {
        let path = (home as NSString).appendingPathComponent("Documents/big-video.mp4")
        let item = makeItem(
            id: "user.video",
            path: path,
            bytes: 8_000_000_000,
            verification: inactiveVerification(sot: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 80,
                semanticType: "USER_VIDEO",
                lifecycle: userContentLifecycle()
            )
        )
        let evidence = ActionArchitecture.evidenceBundle(from: item)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: evidence,
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        )
        XCTAssertTrue(decision.eligible)
        XCTAssertTrue(decision.explanationCodes.contains("SOT_TRUE_ALLOWED"))
        XCTAssertEqual(decision.expectedLocalRecoveryBytes, 0)
        XCTAssertEqual(decision.expectedLogicalBytesMoved, 8_000_000_000)
    }

    func testSOTFalseNotRequiredForMoveToICloud() {
        let path = (home as NSString).appendingPathComponent("Documents/report.pdf")
        let item = makeItem(
            id: "user.doc",
            path: path,
            verification: inactiveVerification(sot: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 80,
                semanticType: "USER_DOCUMENT",
                lifecycle: userContentLifecycle()
            )
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: ActionArchitecture.evidenceBundle(from: item),
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        )
        XCTAssertTrue(decision.eligible)
        XCTAssertFalse(decision.blockedReasons.contains(ActionBlockReason.sourceOfTruthProtected))
    }

    func testLibraryPathBlocksMoveToICloud() {
        let path = (home as NSString).appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
        let item = makeItem(id: "cursor.store", path: path)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path, confidence: 0.5),
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.relocationContractMissing))
    }

    func testSourceActiveBlocksMoveToICloud() {
        let path = (home as NSString).appendingPathComponent("Documents/active.mp4")
        var v = inactiveVerification(sot: .true)
        v.activeState = .active
        v.activeStateConfidence = .verified
        let item = makeItem(id: "active.video", path: path, verification: v)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path, confidence: 0.5),
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.sourceActive))
    }

    func testICloudUnavailableBlocksMoveToICloud() {
        let path = (home as NSString).appendingPathComponent("Documents/file.pdf")
        let item = makeItem(
            id: "doc",
            path: path,
            verification: inactiveVerification(sot: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 80,
                semanticType: "USER_DOCUMENT",
                lifecycle: userContentLifecycle()
            )
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToICloud,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path, confidence: 0.5),
            state: RuntimeState(),
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: false, allowManualReview: true)
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.iCloudUnavailable))
    }

    // MARK: - MOVE_TO_TRASH

    func testDerivedDataStrictProofEligibleForTrash() {
        let path = (home as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData/Runner-abc")
        let item = makeItem(
            id: "deriveddata.runner",
            path: path,
            bytes: 36_000_000,
            bucket: .generated,
            kind: .generatedBuild,
            verification: inactiveVerification(sot: .false, regen: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 90,
                semanticType: "XCODE_DERIVED_DATA",
                lifecycle: generatedLifecycle()
            ),
            safetyClass: .green,
            action: .moveToTrash
        )
        var evidence = EvidenceBundle(canonicalPath: path, confidence: 0.9)
        evidence.openFileHandle = .false
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: evidence,
            state: RuntimeState()
        )
        XCTAssertTrue(decision.eligible)
        XCTAssertEqual(decision.expectedLocalRecoveryBytes, 36_000_000)
    }

    func testRegenerabilityUnknownBlocksTrash() {
        let path = (home as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData/Unknown-xyz")
        let item = makeItem(
            id: "deriveddata.unknown",
            path: path,
            bucket: .generated,
            kind: .generatedBuild,
            verification: inactiveVerification(sot: .false, regen: .unknown),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 90,
                semanticType: "XCODE_DERIVED_DATA",
                lifecycle: generatedLifecycle()
            )
        )
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path, confidence: 0.5),
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.regenerabilityUnknown))
    }

    // MARK: - REMOVE_LOCAL_DOWNLOAD

    func testCloudPathAloneInsufficientForRemoveLocalDownload() {
        let path = (home as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/file.pdf")
        let item = makeItem(id: "cloud.doc", path: path, bucket: .cloud, kind: .cloudLocalMaterialized)
        var evidence = EvidenceBundle(canonicalPath: path, confidence: 0.5)
        evidence.cloudFileProvider = .unknown
        evidence.syncWouldDeleteRemote = .unknown
        evidence.iCloudEvictable = .unknown
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .removeLocalDownload,
            engine: engine,
            evidence: evidence,
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.syncStateUnknown))
    }

    func testRemoveLocalDownloadRequiresFileProviderBacking() {
        let path = "/tmp/local-only-\(UUID().uuidString).pdf"
        let item = makeItem(id: "local", path: path, bucket: .userData)
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .removeLocalDownload,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: path, confidence: 0.5),
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
        XCTAssertTrue(decision.blockedReasons.contains(.fileProviderRequired))
    }

    func testPermanentDeleteDoesNotMapToRemoveLocalDownload() {
        XCTAssertNil(ActionArchitecture.storageAction(from: .permanentDelete))
        XCTAssertNotEqual(ActionArchitecture.storageAction(from: .cloudEvictOnly), .moveToTrash)
    }

    // MARK: - Voice Memo / iOS Backup

    func testVoiceMemoBlocksMoveToICloudAndRecommendsKeep() {
        let path = (home as NSString).appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/rec.m4a")
        let item = makeItem(
            id: "voicememos.recording",
            path: path,
            bytes: 13_000_000_000,
            verification: inactiveVerification(sot: .true)
        )
        let report = ActionPreflightEngine.buildReport(items: [item], engine: engine)
        XCTAssertEqual(report.recommendations.first?.recommendedAction, .keep)
        XCTAssertTrue(report.recommendations.first?.blockedActions.contains {
            $0.action == .moveToICloud && $0.reasons.contains(.voiceMemoNativeSyncRequired)
        } == true)
        XCTAssertTrue(report.previewExecutable == false)
    }

    func testIOSBackupBlocksGenericMoveToICloud() {
        let path = (home as NSString).appendingPathComponent("Library/Application Support/MobileSync/Backup/00008110-001")
        let item = makeItem(
            id: "ios.backup.device",
            path: path,
            bytes: 24_000_000_000,
            bucket: .backup,
            verification: inactiveVerification(sot: .true)
        )
        let rec = ActionRecommendationEngine.recommend(items: [item], engine: engine).first!
        XCTAssertEqual(rec.recommendedAction, .keep)
        XCTAssertTrue(rec.blockedActions.contains {
            $0.action == .moveToICloud && $0.reasons.contains(.iosBackupRequiresDeviceAwareMigration)
        })
    }

    // MARK: - Recommendation quality

    func testLargeUserVideoRecommendsMoveToICloudOverTrash() {
        let path = (home as NSString).appendingPathComponent("Documents/movie.mov")
        let item = makeItem(
            id: "user.movie",
            path: path,
            bytes: 8_000_000_000,
            verification: inactiveVerification(sot: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 80,
                semanticType: "USER_VIDEO",
                lifecycle: userContentLifecycle()
            )
        )
        let rec = ActionRecommendationEngine.recommend(
            items: [item],
            engine: engine,
            evidenceByEntityID: [item.detected.entity.id: ActionArchitecture.evidenceBundle(from: item)],
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        ).first!
        if case .actionable(.moveToICloud) = rec.disposition {
            XCTAssertEqual(rec.recommendedAction, StorageAction.moveToICloud)
        } else {
            XCTFail("Expected MOVE_TO_ICLOUD recommendation for large user video")
        }
    }

    func testDerivedDataRecommendsMoveToTrash() {
        let path = (home as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData/App-xyz")
        let item = makeItem(
            id: "deriveddata.app",
            path: path,
            bytes: 36_000_000,
            bucket: .generated,
            kind: .generatedBuild,
            verification: inactiveVerification(sot: .false, regen: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 90,
                semanticType: "XCODE_DERIVED_DATA",
                lifecycle: generatedLifecycle()
            ),
            safetyClass: .green,
            action: .moveToTrash
        )
        var evidence = EvidenceBundle(canonicalPath: path, confidence: 0.9)
        evidence.openFileHandle = .false
        let rec = ActionRecommendationEngine.recommend(
            items: [item],
            engine: engine,
            evidenceByEntityID: [item.detected.entity.id: evidence]
        ).first!
        if case .actionable(.moveToTrash) = rec.disposition {
            XCTAssertTrue(rec.recommendationReasons.contains("GENERATED_ARTIFACT"))
        } else {
            XCTFail("Expected MOVE_TO_TRASH for DerivedData")
        }
    }

    func testClaudeRuntimeRecommendsKeepOrVerifyMore() {
        let path = (home as NSString).appendingPathComponent("Library/Application Support/Claude/rootfs.img")
        let item = makeItem(
            id: "claude.vm",
            path: path,
            bytes: 10_000_000_000,
            safetyClass: .unknown
        )
        let rec = ActionRecommendationEngine.recommend(items: [item], engine: engine).first!
        XCTAssertEqual(rec.recommendedAction, .keep)
        XCTAssertTrue(rec.blockedActions.contains { $0.action == .moveToICloud })
        XCTAssertTrue(rec.blockedActions.contains { $0.action == .moveToTrash })
    }

    func testRecommendationNeverOverridesSafetyForVoiceMemo() {
        let path = (home as NSString).appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/big.m4a")
        let item = makeItem(
            id: "voicememos.big",
            path: path,
            bytes: 13_000_000_000,
            verification: inactiveVerification(sot: .true)
        )
        let rec = ActionRecommendationEngine.recommend(
            items: [item],
            engine: engine,
            userContext: ActionUserContext(wantsMoreFreeSpace: true, iCloudEnabled: true, allowManualReview: true)
        ).first!
        XCTAssertNotEqual(rec.recommendedAction, .moveToICloud)
        XCTAssertEqual(rec.recommendedAction, .keep)
    }

    func testActionArchitectureReportIsReadOnly() {
        let item = makeItem(id: "x", path: "/tmp/x")
        let report = ActionPreflightEngine.buildReport(items: [item], engine: engine)
        XCTAssertFalse(report.previewExecutable)
        XCTAssertFalse(report.destructiveActionsExecuted)
    }

    func testRedSafetyBlocksEligibleTrashDecision() {
        let path = (home as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData/Red-abc")
        let item = makeItem(
            id: "deriveddata.red",
            path: path,
            bucket: .generated,
            verification: inactiveVerification(sot: .false, regen: .true),
            annotation: DetectionAnnotation(
                detectorID: "test",
                specificity: 90,
                semanticType: "XCODE_DERIVED_DATA",
                lifecycle: generatedLifecycle()
            ),
            safetyClass: .red
        )
        let trashEngine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))
        var evidence = EvidenceBundle(canonicalPath: path, confidence: 0.5)
        evidence.openFileHandle = .false
        let decision = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: trashEngine,
            evidence: evidence,
            state: RuntimeState()
        )
        XCTAssertFalse(decision.eligible)
    }
}
