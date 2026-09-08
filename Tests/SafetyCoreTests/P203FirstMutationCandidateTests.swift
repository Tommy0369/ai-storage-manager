import XCTest
@testable import SafetyCore

final class P203FirstMutationCandidateTests: XCTestCase {
    private func makeItem(
        id: String,
        path: String,
        bytes: Int64 = 1_000_000,
        safetyClass: SafetyClass = .green,
        role: LifecycleRole? = nil
    ) -> ClassifiedItem {
        let entity = StorageEntity(id: id, kind: .userOriginal, category: "USER", subcategory: "Test", displayName: id, path: path, logicalBytes: bytes)
        var annotation: DetectionAnnotation?
        if let role {
            annotation = DetectionAnnotation(
                detectorID: "t",
                specificity: 80,
                semanticType: "TEST",
                lifecycle: LifecycleEvidence(role: role, roleConfidence: .verified)
            )
        }
        let decision = SafetyDecision(
            entity: entity,
            action: .noAction,
            safetyClass: safetyClass,
            safetyScore: SafetyScore(value: 90),
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: "t",
            evaluationLayer: .exactVendor,
            evidenceConfidence: 0.9,
            userExplanationJA: "test",
            growthCauses: [],
            requiresUserApproval: false,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(entity: entity, bucket: .userData, domain: "User", associatedProcesses: [], identified: true, annotation: annotation),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: bytes,
            actionVariants: [:],
            inclusiveBytes: bytes,
            exclusiveBytes: bytes,
            resolution: .l4SemanticEntity
        )
    }

    private func trashDecision(entityID: String, eligible: Bool = true) -> ActionDecision {
        ActionDecision(entityID: entityID, action: .moveToTrash, safetyClass: .green, eligible: eligible)
    }

    private func iCloudDecision(entityID: String, eligible: Bool) -> ActionDecision {
        ActionDecision(entityID: entityID, action: .moveToICloud, safetyClass: eligible ? .green : .unknown, eligible: eligible)
    }

    func testDownloadsRootTooBroadForFirstMutation() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (home as NSString).appendingPathComponent("Downloads")
        let item = makeItem(id: "user.downloads", path: path)
        XCTAssertTrue(FirstMutationCandidateAnalyzer.isBroadAggregateRoot(item))
    }

    func testExactFileNotBroadRoot() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (home as NSString).appendingPathComponent("Downloads/report.pdf")
        let item = makeItem(id: "user.file.report", path: path)
        XCTAssertFalse(FirstMutationCandidateAnalyzer.isBroadAggregateRoot(item))
    }

    func testBlockedCandidateCannotWinRanking() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let blocked = makeItem(id: "git.repo", path: "\(home)/proj/.git", safetyClass: .red)
        let small = makeItem(id: "cache.x", path: "\(home)/Library/Caches/x", bytes: 100, role: .cache)
        let catalog = ActionDecisionCatalog(
            setsByEntityID: [
                blocked.detected.entity.id: ActionDecisionSet(
                    entityID: blocked.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [.moveToTrash: ActionDecision(entityID: blocked.detected.entity.id, action: .moveToTrash, safetyClass: .red, eligible: false)]
                ),
                small.detected.entity.id: ActionDecisionSet(
                    entityID: small.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [.moveToTrash: trashDecision(entityID: small.detected.entity.id)]
                ),
            ],
            telemetry: ActionSafetyEvalDedupReport(
                actionSafetyEvaluatorInvocations: 2, uniqueEntityActionPairs: 2, duplicateEvaluations: 0,
                decisionReuseCount: 0, entitiesEvaluated: 2, buildRuntimeMs: 1
            )
        )
        let result = FirstMutationCandidateAnalyzer.analyze(
            items: [blocked, small],
            decisionCatalog: catalog,
            recommendations: [],
            preflights: [],
            snapshotsByEntityID: [:],
            runtimeResolutions: [:],
            mutationGate: MutationGateReport(entries: [], executorImplemented: false),
            ruleVersion: "t",
            runtimeGeneration: 1
        )
        XCTAssertFalse(result.ranking.entries.contains { $0.entityID == blocked.detected.entity.id })
    }

    func testHigherBytesDoesNotOverrideSafetyBlock() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let hugeBlocked = makeItem(id: "huge.blocked", path: "\(home)/huge", bytes: 999_999_999_999, safetyClass: .unknown)
        let smallEligible = makeItem(id: "small.cache", path: "\(home)/Library/Caches/t", bytes: 1000, role: .cache)
        var hugeDecision = trashDecision(entityID: hugeBlocked.detected.entity.id, eligible: false)
        hugeDecision.safetyClass = .unknown
        let catalog = ActionDecisionCatalog(
            setsByEntityID: [
                hugeBlocked.detected.entity.id: ActionDecisionSet(
                    entityID: hugeBlocked.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [.moveToTrash: hugeDecision]
                ),
                smallEligible.detected.entity.id: ActionDecisionSet(
                    entityID: smallEligible.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [.moveToTrash: trashDecision(entityID: smallEligible.detected.entity.id)]
                ),
            ],
            telemetry: ActionSafetyEvalDedupReport(
                actionSafetyEvaluatorInvocations: 2, uniqueEntityActionPairs: 2, duplicateEvaluations: 0,
                decisionReuseCount: 0, entitiesEvaluated: 2, buildRuntimeMs: 1
            )
        )
        let result = FirstMutationCandidateAnalyzer.analyze(
            items: [hugeBlocked, smallEligible],
            decisionCatalog: catalog,
            recommendations: [],
            preflights: [],
            snapshotsByEntityID: [:],
            runtimeResolutions: [:],
            mutationGate: MutationGateReport(entries: [], executorImplemented: false),
            ruleVersion: "t",
            runtimeGeneration: 1
        )
        if let top = result.ranking.entries.first {
            XCTAssertNotEqual(top.entityID, hugeBlocked.detected.entity.id)
        }
    }

    func testLowBlastRadiusTrashOutranksComplexCloud() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dd = makeItem(id: "xcode.deriveddata.app", path: "\(home)/Library/Developer/Xcode/DerivedData/App-abc", role: .generatedArtifact)
        let file = makeItem(id: "user.video", path: "\(home)/Downloads/movie.mp4", bytes: 5_000_000_000)
        let catalog = ActionDecisionCatalog(
            setsByEntityID: [
                dd.detected.entity.id: ActionDecisionSet(
                    entityID: dd.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [
                        .moveToTrash: trashDecision(entityID: dd.detected.entity.id),
                        .moveToICloud: iCloudDecision(entityID: dd.detected.entity.id, eligible: false),
                    ]
                ),
                file.detected.entity.id: ActionDecisionSet(
                    entityID: file.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [
                        .moveToTrash: ActionDecision(entityID: file.detected.entity.id, action: .moveToTrash, safetyClass: .green, eligible: false),
                        .moveToICloud: iCloudDecision(entityID: file.detected.entity.id, eligible: true),
                    ]
                ),
            ],
            telemetry: ActionSafetyEvalDedupReport(
                actionSafetyEvaluatorInvocations: 4, uniqueEntityActionPairs: 4, duplicateEvaluations: 0,
                decisionReuseCount: 0, entitiesEvaluated: 2, buildRuntimeMs: 1
            )
        )
        let result = FirstMutationCandidateAnalyzer.analyze(
            items: [dd, file],
            decisionCatalog: catalog,
            recommendations: [],
            preflights: [],
            snapshotsByEntityID: [:],
            runtimeResolutions: [:],
            mutationGate: MutationGateReport(entries: [], executorImplemented: false),
            ruleVersion: "t",
            runtimeGeneration: 1
        )
        let trashRank = result.ranking.entries.firstIndex { $0.action == StorageAction.moveToTrash.rawValue }
        let cloudRank = result.ranking.entries.firstIndex { $0.action == StorageAction.moveToICloud.rawValue }
        if let t = trashRank, let c = cloudRank {
            XCTAssertLessThan(t, c)
        }
    }

    func testNoSafeCandidateWhenOnlyDownloadsRoot() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let downloads = makeItem(id: "user.downloads", path: (home as NSString).appendingPathComponent("Downloads"))
        let catalog = ActionDecisionCatalog(
            setsByEntityID: [
                downloads.detected.entity.id: ActionDecisionSet(
                    entityID: downloads.detected.entity.id, snapshotGeneration: 1, evidenceGeneration: 1, runtimeGeneration: 1,
                    decisions: [.moveToICloud: iCloudDecision(entityID: downloads.detected.entity.id, eligible: true)]
                ),
            ],
            telemetry: ActionSafetyEvalDedupReport(
                actionSafetyEvaluatorInvocations: 1, uniqueEntityActionPairs: 1, duplicateEvaluations: 0,
                decisionReuseCount: 0, entitiesEvaluated: 1, buildRuntimeMs: 1
            )
        )
        let result = FirstMutationCandidateAnalyzer.analyze(
            items: [downloads],
            decisionCatalog: catalog,
            recommendations: [],
            preflights: [],
            snapshotsByEntityID: [:],
            runtimeResolutions: [:],
            mutationGate: MutationGateReport(entries: [], executorImplemented: false),
            ruleVersion: "t",
            runtimeGeneration: 1
        )
        XCTAssertEqual(result.selection.outcome, FirstMutationSelectionOutcome.noSafeRealMutationCandidate.rawValue)
        XCTAssertEqual(result.gate.gate, "FIRST_REAL_MUTATION_GATE")
        XCTAssertNil(result.selection.selectedEntityID)
        XCTAssertEqual(result.downloadsAudit?.entityGranularityBlocker, "ENTITY_GRANULARITY_TOO_BROAD")
    }

    func testExecutionPermitStillDisabled() {
        XCTAssertNil(ExecutionPermit.generate(
            receipt: PreflightReceipt(
                receiptID: "t", entityID: "x", action: .moveToTrash,
                bindingFingerprint: ActionBindingFingerprint(
                    entityID: "x", action: .moveToTrash, canonicalPath: "/tmp/x",
                    evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                    ruleVersion: "t", transactionContractVersion: "1"
                ),
                requiredClaims: [], satisfiedClaims: [], missingClaims: [], staleClaims: [], conflictedClaims: [],
                observedAt: Date(), freshnessValidity: [], evidenceGeneration: 1, verificationGeneration: 1,
                runtimeGeneration: 1, result: "OK"
            ),
            approval: UserActionApproval(
                approvalID: "a", entityID: "x", action: .moveToTrash,
                bindingFingerprint: ActionBindingFingerprint(
                    entityID: "x", action: .moveToTrash, canonicalPath: "/tmp/x",
                    evidenceGeneration: 1, verificationGeneration: 1, runtimeGeneration: 1,
                    ruleVersion: "t", transactionContractVersion: "1"
                ),
                consequenceSummaryVersion: "1", expectedRecoveryBytes: nil, approvedAt: Date(),
                expiryPolicy: "session", scope: "single"
            ),
            decision: ActionDecision(entityID: "x", action: .moveToTrash, safetyClass: .green, eligible: true)
        ))
    }
}
