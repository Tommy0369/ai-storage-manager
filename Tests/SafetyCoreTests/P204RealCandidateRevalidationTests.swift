import XCTest
@testable import SafetyCore

final class P204RealCandidateRevalidationTests: XCTestCase {
    private func makeHome() throws -> String {
        let dir = NSTemporaryDirectory() + "asm-p204-\(UUID().uuidString)"
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

    private func emptyGate(status: String = "NO_SAFE_REAL_MUTATION_CANDIDATE") -> FirstRealMutationGateReport {
        FirstRealMutationGateReport(
            gate: "FIRST_REAL_MUTATION_GATE",
            status: status,
            selectedCandidate: nil,
            selectedAction: nil,
            reason: ["test"],
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
    }

    private func cleanDedup() -> ActionSafetyEvalDedupReport {
        ActionSafetyEvalDedupReport(
            actionSafetyEvaluatorInvocations: 0,
            uniqueEntityActionPairs: 0,
            duplicateEvaluations: 0,
            decisionReuseCount: 0,
            entitiesEvaluated: 0,
            buildRuntimeMs: 0
        )
    }

    private func cleanAudit() -> MutationSurfaceAuditReport {
        MutationSurfaceAuditReport(
            scannedFiles: 0,
            findings: [],
            actualMutationImplementations: 0,
            executorImplemented: false,
            auditPassed: true
        )
    }

    func testDiagnosticNeverCreatesCandidate() throws {
        let home = try makeHome()
        let ddRoot = "\(home)/Library/Developer/Xcode/DerivedData"
        try FileManager.default.createDirectory(atPath: ddRoot, withIntermediateDirectories: true)

        let funnel = DerivedDataSurfaceFunnelReport(
            derivedDataRoot: ddRoot,
            rootExists: true,
            filesystemChildCount: 0,
            enumerationBounded: true,
            enumerationMaxChildren: 64,
            enumerationRuntimeMs: 1,
            historicalChecks: [],
            entries: [],
            rootEntityID: "xcode.derived_data",
            rootEntitySurfaced: false,
            concreteSemanticEntityCount: 0,
            scannerObservedChildCount: 0,
            detectorMatchedCount: 0,
            entityEmittedCount: 0,
            proofCandidateCount: 0,
            proofAttemptedCount: 0,
            reportSurfacedCount: 0
        )
        let readiness = DerivedDataMutationReadinessReport(
            entries: [], entitiesDiscovered: 0, moveToTrashSafetyGreen: 0,
            recommendedMoveToTrash: 0, preflightRequired: 0, approvalRequired: 0,
            contractSatisfiedReadOnly: 0, executorImplemented: false
        )

        let report = RealCandidateRevalidationAnalyzer.analyze(
            home: home,
            funnel: funnel,
            readiness: readiness,
            gate: emptyGate(),
            dedup: cleanDedup(),
            surfaceAudit: cleanAudit()
        )

        XCTAssertTrue(report.humanSetupExpected)
        XCTAssertFalse(report.storageManagerCreatedCandidate)
        XCTAssertEqual(report.outcome, RealCandidateRevalidationOutcome.testSetupIncomplete.rawValue)
        XCTAssertFalse(report.executionPermitGenerated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(ddRoot)/Synthetic-Entity"))
    }

    func testEmptyDerivedDataIsTestSetupIncomplete() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let backlog = EntityVerificationBacklogReport(entries: [], totalCandidates: 0, attemptedCount: 0, blockedCount: 0)
        let surface = DerivedDataSurfaceAnalyzer.analyze(
            home: home,
            items: [],
            proofTargets: ["derived-data"],
            catalogRuntime: nil,
            verificationBacklog: backlog
        )
        if surface.funnel.filesystemChildCount == 0 {
            let report = RealCandidateRevalidationAnalyzer.analyze(
                home: home,
                funnel: surface.funnel,
                readiness: DerivedDataMutationReadinessReport(
                    entries: [], entitiesDiscovered: 0, moveToTrashSafetyGreen: 0,
                    recommendedMoveToTrash: 0, preflightRequired: 0, approvalRequired: 0,
                    contractSatisfiedReadOnly: 0, executorImplemented: false
                ),
                gate: emptyGate(),
                dedup: cleanDedup(),
                surfaceAudit: cleanAudit()
            )
            XCTAssertEqual(report.outcome, RealCandidateRevalidationOutcome.testSetupIncomplete.rawValue)
            XCTAssertEqual(report.derivedDataChildrenObserved, 0)
        }
    }

    func testNaturallySurfacedDerivedDataUsesExistingPipeline() throws {
        let home = try makeHome()
        let project = "\(home)/Projects/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let ddPath = try installRunnerFixture(home: home, name: "Runner-p204", workspacePath: project)

        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        let detected = catalog.detectAll(home: home, scanner: ReadOnlyStorageScanner())
        let child = detected.first { $0.entity.path == ddPath }
        XCTAssertNotNil(child)

        let items = detected.map { entity -> ClassifiedItem in
            let decision = SafetyDecision(
                entity: entity.entity,
                action: .noAction,
                safetyClass: .unknown,
                safetyScore: SafetyScore(value: 50),
                reasonCodes: [],
                sideEffects: [],
                matchedRuleID: nil,
                evaluationLayer: .exactVendor,
                evidenceConfidence: 0.5,
                userExplanationJA: "test",
                growthCauses: [],
                requiresUserApproval: false,
                blockedBy: nil
            )
            return ClassifiedItem(
                detected: entity,
                decision: decision,
                semantic: SemanticResult(from: decision),
                allocatedBytes: entity.entity.logicalBytes,
                actionVariants: [:],
                inclusiveBytes: entity.entity.logicalBytes,
                exclusiveBytes: entity.entity.logicalBytes,
                resolution: .l4SemanticEntity
            )
        }
        let backlog = EntityVerificationBacklogReport(entries: [], totalCandidates: 0, attemptedCount: 0, blockedCount: 0)
        let surface = DerivedDataSurfaceAnalyzer.analyze(
            home: home,
            items: items,
            proofTargets: ["derived-data"],
            catalogRuntime: DetectorCatalog.lastCatalogTelemetry,
            verificationBacklog: backlog
        )
        XCTAssertEqual(surface.funnel.filesystemChildCount, 1)
        XCTAssertEqual(surface.funnel.detectorMatchedCount, 1)
        XCTAssertGreaterThanOrEqual(surface.funnel.concreteSemanticEntityCount, 1)
    }

    func testXcodeActiveBlocksReadinessClassification() {
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
            activeState: "active",
            activeStateConfidence: "verified",
            openFileState: "false",
            openFileConfidence: "verified",
            xcodeRunning: "running",
            xcodebuildRunning: "inactive",
            evidenceFreshness: "resolved",
            evidenceCompleteness: "complete",
            evidenceConflicts: false,
            moveToTrashSafetyClass: "green",
            moveToTrashEligible: true,
            matchedRuleID: "derived_data_trash",
            recommendation: "MOVE_TO_TRASH",
            recommendationDisposition: "actionable:MOVE_TO_TRASH",
            preflightAllowed: true,
            mutationReadiness: MutationReadiness.preflightRequired.rawValue,
            firstBlockingGate: "xcode_inactive_verified",
            allBlockingReasons: ["xcode_inactive_verified", "RUNTIME_ACTIVE"],
            gateSteps: [],
            transactionContractAvailable: true,
            postVerifyContractAvailable: true,
            auditContractAvailable: true,
            bindingFingerprintPossible: true,
            rootCauseCategory: "REAL_STATE_CHANGED",
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
        let diagnostic = RealCandidateRevalidationAnalyzer.buildChildDiagnostic(
            funnelEntry: funnelEntry,
            readiness: entry,
            scanTimestamp: Date(),
            createdTimestamp: nil
        )
        XCTAssertEqual(diagnostic.blockerClassification, RealCandidateBlockerClass.realRuntimeStateBlock.rawValue)
        XCTAssertEqual(diagnostic.xcodeRunning, "running")
    }

    func testExternalSetupFlagNeverGrantsSafety() throws {
        let home = try makeHome()
        let project = "\(home)/ws/App.xcodeproj"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        _ = try installRunnerFixture(home: home, name: "Runner-flag", workspacePath: project)

        let funnel = DerivedDataSurfaceFunnelReport(
            derivedDataRoot: "\(home)/Library/Developer/Xcode/DerivedData",
            rootExists: true,
            filesystemChildCount: 1,
            enumerationBounded: true,
            enumerationMaxChildren: 64,
            enumerationRuntimeMs: 1,
            historicalChecks: [],
            entries: [
                DerivedDataSurfaceFunnelEntry(
                    path: "\(home)/Library/Developer/Xcode/DerivedData/Runner-flag",
                    childName: "Runner-flag",
                    filesystemObserved: true,
                    scannerObserved: true,
                    detectorCandidate: true,
                    detectorMatched: true,
                    entityEmitted: true,
                    entityDeduplicated: false,
                    entityDroppedReason: nil,
                    proofCandidate: true,
                    proofAttempted: false,
                    proofResult: nil,
                    reportSurfaced: true,
                    finalEntityID: "xcode.deriveddata.Runner-flag",
                    infoPlistPresent: true,
                    workspacePathPresent: true,
                    workspaceExists: true,
                    measurementKnown: true
                ),
            ],
            rootEntityID: "xcode.derived_data",
            rootEntitySurfaced: true,
            concreteSemanticEntityCount: 1,
            scannerObservedChildCount: 1,
            detectorMatchedCount: 1,
            entityEmittedCount: 1,
            proofCandidateCount: 1,
            proofAttemptedCount: 0,
            reportSurfacedCount: 1
        )
        let report = RealCandidateRevalidationAnalyzer.analyze(
            home: home,
            funnel: funnel,
            readiness: DerivedDataMutationReadinessReport(
                entries: [], entitiesDiscovered: 0, moveToTrashSafetyGreen: 0,
                recommendedMoveToTrash: 0, preflightRequired: 0, approvalRequired: 0,
                contractSatisfiedReadOnly: 0, executorImplemented: false
            ),
            gate: emptyGate(),
            dedup: cleanDedup(),
            surfaceAudit: cleanAudit()
        )
        XCTAssertTrue(report.humanSetupExpected)
        XCTAssertFalse(report.storageManagerCreatedCandidate)
        XCTAssertNotEqual(report.outcome, RealCandidateRevalidationOutcome.readyForHumanAuthorization.rawValue)
        XCTAssertEqual(report.approvalRequired, 0)
    }

    func testReadyGateDoesNotGenerateExecutionPermit() {
        let gate = FirstRealMutationGateReport(
            gate: "FIRST_REAL_MUTATION_GATE",
            status: P21GateStatusValue.readyForHumanAuthorization.rawValue,
            selectedCandidate: "xcode.deriveddata.Test",
            selectedAction: "MOVE_TO_TRASH",
            reason: ["Candidate reached approval gate"],
            selectionOutcome: FirstMutationSelectionOutcome.readyCandidateFound.rawValue,
            approvalRequiredCount: 1,
            contractSatisfiedReadOnlyCount: 0,
            preflightRequiredCount: 0,
            rankingEligibleCount: 1,
            executorImplemented: false,
            previewExecutable: false,
            destructiveActionsExecuted: false,
            realDerivedDataCandidates: 1,
            approvalRequired: 1,
            contractSatisfiedReadOnly: 0,
            topBlockers: []
        )
        let funnel = DerivedDataSurfaceFunnelReport(
            derivedDataRoot: "/tmp/DerivedData",
            rootExists: true,
            filesystemChildCount: 1,
            enumerationBounded: true,
            enumerationMaxChildren: 64,
            enumerationRuntimeMs: 1,
            historicalChecks: [],
            entries: [],
            rootEntityID: "xcode.derived_data",
            rootEntitySurfaced: true,
            concreteSemanticEntityCount: 1,
            scannerObservedChildCount: 1,
            detectorMatchedCount: 1,
            entityEmittedCount: 1,
            proofCandidateCount: 1,
            proofAttemptedCount: 1,
            reportSurfacedCount: 1
        )
        let report = RealCandidateRevalidationAnalyzer.analyze(
            home: "/tmp",
            funnel: funnel,
            readiness: DerivedDataMutationReadinessReport(
                entries: [], entitiesDiscovered: 1, moveToTrashSafetyGreen: 1,
                recommendedMoveToTrash: 1, preflightRequired: 0, approvalRequired: 1,
                contractSatisfiedReadOnly: 0, executorImplemented: false
            ),
            gate: gate,
            dedup: cleanDedup(),
            surfaceAudit: cleanAudit()
        )
        XCTAssertEqual(report.outcome, RealCandidateRevalidationOutcome.readyForHumanAuthorization.rawValue)
        XCTAssertFalse(report.executionPermitGenerated)
        XCTAssertFalse(report.storageManagerCreatedCandidate)
    }

    func testSemanticSurfaceFailureWhenFilesystemExistsButNoEntities() {
        let funnel = DerivedDataSurfaceFunnelReport(
            derivedDataRoot: "/tmp/DerivedData",
            rootExists: true,
            filesystemChildCount: 2,
            enumerationBounded: true,
            enumerationMaxChildren: 64,
            enumerationRuntimeMs: 1,
            historicalChecks: [],
            entries: [
                DerivedDataSurfaceFunnelEntry(
                    path: "/tmp/DerivedData/A", childName: "A",
                    filesystemObserved: true, scannerObserved: false,
                    detectorCandidate: true, detectorMatched: false,
                    entityEmitted: false, entityDeduplicated: true,
                    entityDroppedReason: "NOT_OBSERVED_BY_PROOF_DETECTOR",
                    proofCandidate: false, proofAttempted: false, proofResult: nil,
                    reportSurfaced: false, finalEntityID: nil,
                    infoPlistPresent: false, workspacePathPresent: false,
                    workspaceExists: nil, measurementKnown: nil
                ),
            ],
            rootEntityID: "xcode.derived_data",
            rootEntitySurfaced: true,
            concreteSemanticEntityCount: 0,
            scannerObservedChildCount: 0,
            detectorMatchedCount: 0,
            entityEmittedCount: 0,
            proofCandidateCount: 0,
            proofAttemptedCount: 0,
            reportSurfacedCount: 0
        )
        let report = RealCandidateRevalidationAnalyzer.analyze(
            home: "/tmp",
            funnel: funnel,
            readiness: DerivedDataMutationReadinessReport(
                entries: [], entitiesDiscovered: 0, moveToTrashSafetyGreen: 0,
                recommendedMoveToTrash: 0, preflightRequired: 0, approvalRequired: 0,
                contractSatisfiedReadOnly: 0, executorImplemented: false
            ),
            gate: emptyGate(),
            dedup: cleanDedup(),
            surfaceAudit: cleanAudit()
        )
        XCTAssertEqual(report.outcome, RealCandidateRevalidationOutcome.semanticSurfaceFailure.rawValue)
        XCTAssertTrue(report.architecturalRegressionSuspected)
    }
}
