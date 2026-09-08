import Foundation

public enum RealCandidateBlockerClass: String, Codable, Sendable {
    case realRuntimeStateBlock = "REAL_RUNTIME_STATE_BLOCK"
    case missingExplicitWorkspaceRelationship = "MISSING_EXPLICIT_WORKSPACE_RELATIONSHIP"
    case sourceMissing = "SOURCE_MISSING"
    case sotProofIncomplete = "SOT_PROOF_INCOMPLETE"
    case regenProofIncomplete = "REGEN_PROOF_INCOMPLETE"
    case openStateIncomplete = "OPEN_STATE_INCOMPLETE"
    case evidenceConflict = "EVIDENCE_CONFLICT"
    case semanticSurfaceFailure = "SEMANTIC_SURFACE_FAILURE"
    case otherRealEvidenceBlock = "OTHER_REAL_EVIDENCE_BLOCK"
}

public enum RealCandidateRevalidationOutcome: String, Codable, Sendable {
    case readyForHumanAuthorization = "READY_FOR_HUMAN_AUTHORIZATION"
    case blockedByRealEvidence = "BLOCKED_BY_REAL_EVIDENCE"
    case semanticSurfaceFailure = "SEMANTIC_SURFACE_FAILURE"
    case testSetupIncomplete = "TEST_SETUP_INCOMPLETE"
}

public struct RealCandidateChildDiagnostic: Codable, Sendable, Equatable {
    public var entityID: String?
    public var canonicalPath: String
    public var childName: String
    public var filesystemObserved: Bool
    public var createdTimestamp: String?
    public var observedTimestamp: String
    public var semanticIdentity: String?
    public var scannerObserved: Bool
    public var detectorMatched: Bool
    public var entitySurfaced: Bool
    public var workspacePathPresent: Bool
    public var workspacePathTarget: String?
    public var sourceExists: Bool?
    public var generatedBy: String?
    public var derivedFrom: String?
    public var sourceOfTruth: String?
    public var sourceOfTruthConfidence: String?
    public var regenerability: String?
    public var regenerabilityConfidence: String?
    public var activeState: String?
    public var activeStateConfidence: String?
    public var openFileState: String?
    public var openFileConfidence: String?
    public var xcodeRunning: String?
    public var xcodebuildRunning: String?
    public var evidenceFreshness: String?
    public var evidenceCompleteness: String?
    public var moveToTrashSafety: String?
    public var moveToTrashEligible: Bool?
    public var matchedRule: String?
    public var actionDecision: String?
    public var recommendation: String?
    public var recommendationDisposition: String?
    public var preflightAllowed: Bool?
    public var mutationReadiness: String?
    public var firstBlocker: String?
    public var allBlockers: [String]
    public var blockerClassification: String?
    public var transactionContractAvailable: Bool?
    public var postVerifyContractAvailable: Bool?
    public var auditContractAvailable: Bool?
    public var bindingFingerprintReady: Bool?
    public var executorImplemented: Bool
}

public struct RealCandidateRevalidationReport: Codable, Sendable, Equatable {
    public var phase: String
    public var humanSetupExpected: Bool
    public var storageManagerCreatedCandidate: Bool
    public var derivedDataRootExists: Bool
    public var derivedDataRootPath: String
    public var derivedDataChildrenObserved: Int
    public var newlyObservedChildren: [String]
    public var semanticEntitiesSurfaced: Int
    public var proofCandidates: Int
    public var workspacePathVerified: Int
    public var workspaceRelationVerified: Int
    public var sourceExistsVerified: Int
    public var sotFalseVerified: Int
    public var regenTrueVerified: Int
    public var runtimeInactiveVerified: Int
    public var runtimeActiveBlockCount: Int
    public var openSafeVerified: Int
    public var moveToTrashGreen: Int
    public var recommendedMoveToTrash: Int
    public var preflightRequired: Int
    public var approvalRequired: Int
    public var contractSatisfiedReadOnly: Int
    public var firstRealMutationGateStatus: String
    public var selectedCandidate: String?
    public var selectedAction: String?
    public var outcome: String
    public var outcomeExplanation: String
    public var executionPermitGenerated: Bool
    public var children: [RealCandidateChildDiagnostic]
    public var topBlockerClassifications: [String]
    public var architecturalRegressionSuspected: Bool
}

public enum RealCandidateRevalidationAnalyzer {
    public static func analyze(
        home: String,
        funnel: DerivedDataSurfaceFunnelReport,
        readiness: DerivedDataMutationReadinessReport,
        gate: FirstRealMutationGateReport,
        dedup: ActionSafetyEvalDedupReport,
        surfaceAudit: MutationSurfaceAuditReport,
        scanTimestamp: Date = Date()
    ) -> RealCandidateRevalidationReport {
        let readinessByID = Dictionary(uniqueKeysWithValues: readiness.entries.map { ($0.entityID, $0) })
        let readinessByPath = Dictionary(uniqueKeysWithValues: readiness.entries.map { ($0.canonicalPath, $0) })

        var children: [RealCandidateChildDiagnostic] = []
        var workspacePathVerified = 0
        var workspaceRelationVerified = 0
        var sourceExistsVerified = 0
        var sotFalseVerified = 0
        var regenTrueVerified = 0
        var runtimeInactiveVerified = 0
        var runtimeActiveBlockCount = 0
        var openSafeVerified = 0
        var blockerCounts: [String: Int] = [:]

        for entry in funnel.entries {
            let readinessEntry = entry.finalEntityID.flatMap { readinessByID[$0] }
                ?? readinessByPath[entry.path]
            let created = filesystemCreatedTimestamp(path: entry.path)
            let diagnostic = buildChildDiagnostic(
                funnelEntry: entry,
                readiness: readinessEntry,
                scanTimestamp: scanTimestamp,
                createdTimestamp: created
            )
            children.append(diagnostic)

            if entry.workspacePathPresent, entry.workspaceExists == true { workspacePathVerified += 1 }
            if readinessEntry?.derivedFrom != nil,
               readinessEntry?.sourceWorkspaceExists == true { workspaceRelationVerified += 1 }
            if readinessEntry?.sourceWorkspaceExists == true { sourceExistsVerified += 1 }
            if readinessEntry?.sourceOfTruth == "false",
               readinessEntry?.sourceOfTruthConfidence == "verified" { sotFalseVerified += 1 }
            if readinessEntry?.regenerability == "true",
               readinessEntry?.regenerabilityConfidence == "verified" { regenTrueVerified += 1 }
            if readinessEntry?.xcodeRunning == "inactive",
               readinessEntry?.xcodebuildRunning == "inactive" { runtimeInactiveVerified += 1 }
            if readinessEntry?.xcodeRunning == "running"
                || readinessEntry?.xcodebuildRunning == "running"
                || diagnostic.blockerClassification == RealCandidateBlockerClass.realRuntimeStateBlock.rawValue {
                runtimeActiveBlockCount += 1
            }
            if readinessEntry?.openFileState == "false",
               readinessEntry?.openFileConfidence == "verified" { openSafeVerified += 1 }
            if let cls = diagnostic.blockerClassification {
                blockerCounts[cls, default: 0] += 1
            }
        }

        let outcome = classifyOutcome(
            funnel: funnel,
            gate: gate,
            children: children,
            dedup: dedup,
            surfaceAudit: surfaceAudit
        )

        return RealCandidateRevalidationReport(
            phase: "P2.0.4",
            humanSetupExpected: true,
            storageManagerCreatedCandidate: false,
            derivedDataRootExists: funnel.rootExists,
            derivedDataRootPath: funnel.derivedDataRoot,
            derivedDataChildrenObserved: funnel.filesystemChildCount,
            newlyObservedChildren: funnel.entries.map(\.childName).sorted(),
            semanticEntitiesSurfaced: funnel.concreteSemanticEntityCount,
            proofCandidates: funnel.proofCandidateCount,
            workspacePathVerified: workspacePathVerified,
            workspaceRelationVerified: workspaceRelationVerified,
            sourceExistsVerified: sourceExistsVerified,
            sotFalseVerified: sotFalseVerified,
            regenTrueVerified: regenTrueVerified,
            runtimeInactiveVerified: runtimeInactiveVerified,
            runtimeActiveBlockCount: runtimeActiveBlockCount,
            openSafeVerified: openSafeVerified,
            moveToTrashGreen: readiness.moveToTrashSafetyGreen,
            recommendedMoveToTrash: readiness.recommendedMoveToTrash,
            preflightRequired: readiness.preflightRequired,
            approvalRequired: readiness.approvalRequired,
            contractSatisfiedReadOnly: readiness.contractSatisfiedReadOnly,
            firstRealMutationGateStatus: gate.status,
            selectedCandidate: gate.selectedCandidate,
            selectedAction: gate.selectedAction,
            outcome: outcome.outcome.rawValue,
            outcomeExplanation: outcome.explanation,
            executionPermitGenerated: false,
            children: children.sorted { $0.canonicalPath < $1.canonicalPath },
            topBlockerClassifications: blockerCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key),
            architecturalRegressionSuspected: outcome.architecturalRegressionSuspected
        )
    }

    static func buildChildDiagnostic(
        funnelEntry: DerivedDataSurfaceFunnelEntry,
        readiness: DerivedDataMutationReadinessEntry?,
        scanTimestamp: Date,
        createdTimestamp: String?
    ) -> RealCandidateChildDiagnostic {
        let iso = ISO8601DateFormatter()
        let allBlockers = readiness?.allBlockingReasons ?? surfaceBlockers(funnelEntry: funnelEntry)
        let firstBlocker = readiness?.firstBlockingGate ?? allBlockers.first
        let classification = classifyBlocker(
            funnelEntry: funnelEntry,
            readiness: readiness,
            allBlockers: allBlockers
        )

        return RealCandidateChildDiagnostic(
            entityID: funnelEntry.finalEntityID ?? readiness?.entityID,
            canonicalPath: readiness?.canonicalPath ?? funnelEntry.path,
            childName: funnelEntry.childName,
            filesystemObserved: funnelEntry.filesystemObserved,
            createdTimestamp: createdTimestamp,
            observedTimestamp: iso.string(from: scanTimestamp),
            semanticIdentity: readiness?.semanticIdentity,
            scannerObserved: funnelEntry.scannerObserved,
            detectorMatched: funnelEntry.detectorMatched,
            entitySurfaced: funnelEntry.reportSurfaced || funnelEntry.entityEmitted,
            workspacePathPresent: funnelEntry.workspacePathPresent,
            workspacePathTarget: readiness?.sourceWorkspace,
            sourceExists: readiness?.sourceWorkspaceExists ?? funnelEntry.workspaceExists,
            generatedBy: readiness?.generatedBy,
            derivedFrom: readiness?.derivedFrom,
            sourceOfTruth: readiness?.sourceOfTruth,
            sourceOfTruthConfidence: readiness?.sourceOfTruthConfidence,
            regenerability: readiness?.regenerability,
            regenerabilityConfidence: readiness?.regenerabilityConfidence,
            activeState: readiness?.activeState,
            activeStateConfidence: readiness?.activeStateConfidence,
            openFileState: readiness?.openFileState,
            openFileConfidence: readiness?.openFileConfidence,
            xcodeRunning: readiness?.xcodeRunning,
            xcodebuildRunning: readiness?.xcodebuildRunning,
            evidenceFreshness: readiness?.evidenceFreshness,
            evidenceCompleteness: readiness?.evidenceCompleteness,
            moveToTrashSafety: readiness?.moveToTrashSafetyClass,
            moveToTrashEligible: readiness?.moveToTrashEligible,
            matchedRule: readiness?.matchedRuleID,
            actionDecision: readiness.map { "\($0.moveToTrashSafetyClass ?? "?") eligible=\($0.moveToTrashEligible)" },
            recommendation: readiness?.recommendation,
            recommendationDisposition: readiness?.recommendationDisposition,
            preflightAllowed: readiness?.preflightAllowed,
            mutationReadiness: readiness?.mutationReadiness,
            firstBlocker: firstBlocker,
            allBlockers: allBlockers,
            blockerClassification: classification?.rawValue,
            transactionContractAvailable: readiness?.transactionContractAvailable,
            postVerifyContractAvailable: readiness?.postVerifyContractAvailable,
            auditContractAvailable: readiness?.auditContractAvailable,
            bindingFingerprintReady: readiness?.bindingFingerprintPossible,
            executorImplemented: false
        )
    }

    static func surfaceBlockers(funnelEntry: DerivedDataSurfaceFunnelEntry) -> [String] {
        var blockers: [String] = []
        if !funnelEntry.detectorMatched { blockers.append("DETECTOR_NOT_MATCHED") }
        if !funnelEntry.reportSurfaced { blockers.append("ENTITY_NOT_SURFACED") }
        if !funnelEntry.infoPlistPresent { blockers.append("NO_INFO_PLIST") }
        if !funnelEntry.workspacePathPresent { blockers.append("WORKSPACE_PATH_ABSENT") }
        if funnelEntry.workspaceExists == false { blockers.append("SOURCE_WORKSPACE_MISSING") }
        if let reason = funnelEntry.entityDroppedReason { blockers.append(reason) }
        return blockers
    }

    static func classifyBlocker(
        funnelEntry: DerivedDataSurfaceFunnelEntry,
        readiness: DerivedDataMutationReadinessEntry?,
        allBlockers: [String]
    ) -> RealCandidateBlockerClass? {
        if funnelEntry.filesystemObserved, !funnelEntry.entityEmitted, !funnelEntry.reportSurfaced {
            return .semanticSurfaceFailure
        }

        let sotVerified = readiness?.sourceOfTruth == "false"
            && readiness?.sourceOfTruthConfidence == "verified"
        let regenVerified = readiness?.regenerability == "true"
            && readiness?.regenerabilityConfidence == "verified"

        if sotVerified && regenVerified {
            if readiness?.xcodeRunning == "running"
                || readiness?.xcodebuildRunning == "running"
                || allBlockers.contains("SOURCE_ACTIVE")
                || allBlockers.contains("SOURCE_OPEN")
                || readiness?.firstBlockingGate == "xcode_inactive_verified"
                || readiness?.firstBlockingGate == "open_file_safe_verified" {
                return .realRuntimeStateBlock
            }
        }

        if !funnelEntry.workspacePathPresent || allBlockers.contains("WORKSPACE_PATH_ABSENT") {
            return .missingExplicitWorkspaceRelationship
        }
        if funnelEntry.workspaceExists == false || allBlockers.contains("SOURCE_WORKSPACE_MISSING") {
            return .sourceMissing
        }
        if !sotVerified {
            if readiness != nil { return .sotProofIncomplete }
        }
        if !regenVerified {
            if readiness != nil {
                return sotVerified ? .otherRealEvidenceBlock : .regenProofIncomplete
            }
        }
        if readiness?.openFileState != "false"
            || readiness?.openFileConfidence != "verified"
            || allBlockers.contains("SOURCE_OPEN") {
            if readiness != nil, sotVerified, regenVerified { return .openStateIncomplete }
        }
        if readiness?.evidenceConflicts == true { return .evidenceConflict }
        if readiness != nil, readiness?.mutationReadiness != MutationReadiness.approvalRequired.rawValue,
           readiness?.mutationReadiness != MutationReadiness.contractSatisfiedReadOnly.rawValue {
            return .otherRealEvidenceBlock
        }
        if !allBlockers.isEmpty { return .otherRealEvidenceBlock }
        return nil
    }

    static func classifyOutcome(
        funnel: DerivedDataSurfaceFunnelReport,
        gate: FirstRealMutationGateReport,
        children: [RealCandidateChildDiagnostic],
        dedup: ActionSafetyEvalDedupReport,
        surfaceAudit: MutationSurfaceAuditReport
    ) -> (outcome: RealCandidateRevalidationOutcome, explanation: String, architecturalRegressionSuspected: Bool) {
        if dedup.duplicateEvaluations > 0 || !surfaceAudit.auditPassed {
            return (
                .blockedByRealEvidence,
                "Architecture integrity check failed — duplicateEvaluations=\(dedup.duplicateEvaluations) auditPassed=\(surfaceAudit.auditPassed)",
                true
            )
        }

        if gate.status == P21GateStatusValue.readyForHumanAuthorization.rawValue {
            return (
                .readyForHumanAuthorization,
                "DerivedData candidate reached read-only approval gate. STOP — human authorization is the only next gate. Executor must not start.",
                false
            )
        }

        if funnel.filesystemChildCount == 0 {
            return (
                .testSetupIncomplete,
                "No DerivedData direct children on filesystem. Human Xcode build required before revalidation. storageManagerCreatedCandidate=false.",
                false
            )
        }

        let surfaced = funnel.concreteSemanticEntityCount
        if funnel.filesystemChildCount > 0, surfaced == 0 {
            let detectorMiss = funnel.detectorMatchedCount == 0
            return (
                .semanticSurfaceFailure,
                detectorMiss
                    ? "Filesystem children exist but semantic pipeline did not surface entities — investigate detector/catalog regression."
                    : "Filesystem children exist but zero concrete semantic entities in final catalog — investigate dedup/reporting regression.",
                true
            )
        }

        if funnel.filesystemChildCount > 0,
           funnel.detectorMatchedCount > 0,
           funnel.reportSurfacedCount < funnel.detectorMatchedCount {
            return (
                .semanticSurfaceFailure,
                "Detector emitted entities but not all reached final report — possible reporting regression.",
                true
            )
        }

        return (
            .blockedByRealEvidence,
            "DerivedData surfaced (\(surfaced) semantic entities) but strict evidence blocks first mutation gate: \(gate.status). Believe the evidence.",
            false
        )
    }

    static func filesystemCreatedTimestamp(path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let created = attrs[.creationDate] as? Date else { return nil }
        return ISO8601DateFormatter().string(from: created)
    }
}
