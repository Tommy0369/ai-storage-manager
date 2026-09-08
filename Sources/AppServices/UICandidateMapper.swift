import Foundation
import SafetyCore

/// Maps canonical SafetyCore results to user-facing presentation. No Safety inference.
public enum UICandidateMapper {
    public static func mapReport(_ report: ReadOnlyAnalysisReport) -> (
        overview: StorageOverviewState,
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        history: [UIActionHistoryItem]
    ) {
        var safe: [UICandidateItem] = []
        var review: [UICandidateItem] = []
        var protected: [UICandidateItem] = []

        let gateByKey = Dictionary(
            report.mutationGate.entries.map { ("\($0.entityID):\($0.action)", $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        for item in report.items {
            let gate = gateByKey["\(item.detected.entity.id):\(StorageAction.moveToTrash.rawValue)"]
            let candidate = mapItem(item, gate: gate, report: report)
            switch candidate.group {
            case .safeActions: safe.append(candidate)
            case .reviewNeeded: review.append(candidate)
            case .protected: protected.append(candidate)
            }
        }

        safe.sort { ($0.expectedBytes ?? 0) > ($1.expectedBytes ?? 0) }
        review.sort { ($0.expectedBytes ?? 0) > ($1.expectedBytes ?? 0) }
        protected.sort { $0.displayName < $1.displayName }

        let overview = StorageOverviewState(
            observedBytes: report.coverage.scannedBytes,
            observedBytesLabel: byteLabel(report.coverage.scannedBytes),
            safeActionCount: safe.count,
            reviewCount: review.count,
            protectedCount: protected.count,
            lastScanAt: Date(),
            scanRuntimeSeconds: report.scanRuntimeSeconds
        )

        let history = mapHistory(report.actionHistory, closed: report.postMutationVerification.results)
        return (overview, safe, review, protected, history)
    }

    public static func mapItem(
        _ item: ClassifiedItem,
        gate: MutationGateResult?,
        report: ReadOnlyAnalysisReport? = nil
    ) -> UICandidateItem {
        let entityID = item.detected.entity.id
        let path = item.detected.entity.path
        let safetyClass = item.decision.safetyClass
        let group = classifyGroup(item: item, gate: gate)
        let readiness = mapReadiness(gate: gate, safetyClass: safetyClass, group: group)
        let action: StorageAction? = {
            if ActionExecutionPolicy.allowsFirstMutationTrash(entityID: entityID, path: path),
               gate?.executorImplemented == true || gate?.action == StorageAction.moveToTrash.rawValue {
                return .moveToTrash
            }
            if ActionPolicy.isOllamaModelEntity(entityID: entityID, path: path),
               gate?.action == StorageAction.vendorNativeCleanup.rawValue,
               gate?.executorImplemented == true {
                return .vendorNativeCleanup
            }
            // Prefer vendor-native recommendation from decision even if gate not yet APPROVAL_REQUIRED.
            if ActionPolicy.isOllamaModelEntity(entityID: entityID, path: path),
               item.verification?.remoteReacquisitionProof?.isStrictVerified == true {
                return .vendorNativeCleanup
            }
            return nil
        }()

        return UICandidateItem(
            id: entityID,
            entityID: entityID,
            displayName: humanDisplayName(item),
            category: humanCategory(item),
            pathSummary: pathSummary(path),
            fullPath: path,
            byteLabel: byteLabel(item.exclusiveBytes),
            expectedBytes: item.exclusiveBytes,
            recommendedAction: action,
            recommendedActionLabel: {
                switch action {
                case .moveToTrash: return "Move to Trash"
                case .vendorNativeCleanup:
                    if item.verification?.vendorProofNotes.contains(where: {
                        $0.contains("VENDOR_ABSENT_MANAGED_DATA_REMAINS")
                    }) == true {
                        return "Restore Ollama Management"
                    }
                    if item.verification?.vendorProofNotes.contains(where: {
                        $0.contains("VENDOR_RESTORED_MODEL_UNRECOGNIZED")
                    }) == true {
                        return OllamaRestoreUXLabel.moreVerificationRequired
                    }
                    if gate?.readiness == MutationReadiness.approvalRequired.rawValue
                        || gate?.readiness == MutationReadiness.contractSatisfiedReadOnly.rawValue {
                        return OllamaRestoreUXLabel.removeOllamaModel
                    }
                    return "Remove with Ollama"
                default: return "No action available"
                }
            }(),
            reasonSummary: reasonSummary(item, gate: gate),
            readiness: readiness,
            group: group,
            safetyClass: safetyClass,
            evidenceLines: evidenceLines(item, gate: gate),
            executorAvailable: gate?.executorImplemented ?? false
        )
    }

    public static func mapDetail(_ item: UICandidateItem, gate: MutationGateResult?) -> UICandidateDetail {
        UICandidateDetail(
            item: item,
            consequenceCopy: moveToTrashConsequence(for: item),
            recoverySemantics: recoverySemantics(for: item),
            reversibilityCopy: "This item will be moved to the Trash, not permanently deleted. You can restore it from the Trash in Finder.",
            technicalDetails: UITechnicalDetails(
                entityID: item.entityID,
                canonicalPath: item.fullPath,
                safetyClass: item.safetyClass.rawValue,
                readiness: item.readiness.rawValue,
                gateReadiness: gate?.readiness,
                bindingFingerprintSummary: gate?.actionBindingFingerprint.map {
                    "\($0.entityID) @ \($0.canonicalPath)"
                },
                auditID: nil,
                postVerificationState: nil
            )
        )
    }

    public static func mapPreflight(
        _ result: FreshReadOnlyPreflightEngine.RunResult,
        action: StorageAction
    ) -> UIPreflightResult {
        let readiness = mapGateReadiness(result.freshGateResult.readiness)
        let satisfied = preflightLines(from: result, satisfied: true)
        let blocking = preflightLines(from: result, satisfied: false)
        let canApprove = readiness == .approvalRequired
            && result.receipt.result == PreflightResultCode.satisfiedReadOnly.rawValue
        let message: String
        if canApprove {
            message = "Ready for your approval"
        } else if let blocker = result.firstBlocker {
            message = blockingMessage(for: blocker)
        } else {
            message = "Safety check incomplete"
        }
        return UIPreflightResult(
            entityID: result.session.entityID,
            action: action,
            readiness: readiness,
            satisfiedLines: satisfied,
            blockingLines: blocking,
            bindingFingerprint: result.freshBindingFingerprint,
            receipt: result.receipt,
            canApprove: canApprove,
            userMessage: message
        )
    }

    public static func mapExecutionOutcome(
        report: ActFirstMutationExecutionReport?,
        postResult: PostMutationVerificationResult?,
        error: String?
    ) -> UIExecutionOutcome {
        if let error {
            return UIExecutionOutcome(
                entityID: report?.entityID ?? "",
                action: .moveToTrash,
                readiness: .failed,
                logicalActionCompleted: false,
                storageRecoveryState: .notMeasured,
                recoveryLabel: "Nothing was moved",
                potentialRecoveryLabel: nil,
                movedBytesLabel: nil,
                trashWarning: nil,
                userLines: [error],
                executionReport: report,
                postVerification: postResult,
                errorMessage: error
            )
        }
        guard let post = postResult ?? report?.postMutationVerification else {
            return UIExecutionOutcome(
                entityID: report?.entityID ?? "",
                action: .moveToTrash,
                readiness: .postVerifyPending,
                logicalActionCompleted: false,
                storageRecoveryState: .notMeasured,
                recoveryLabel: "Verifying…",
                potentialRecoveryLabel: nil,
                movedBytesLabel: nil,
                trashWarning: nil,
                userLines: ["Moved. Verifying…"],
                executionReport: report,
                postVerification: nil,
                errorMessage: nil
            )
        }

        let readiness: UIReadinessState
        if post.entityRegenerated {
            readiness = .regenerated
        } else if post.storageRecoveryState == .recoveryPending {
            readiness = .storageRecoveryPending
        } else if post.logicalActionCompleted {
            readiness = .completed
        } else {
            readiness = .failed
        }

        let potential = post.expectedBytes.map { "Potential recovery: \(byteLabel($0))" }
        let moved = post.expectedBytes.map { "Moved to Trash: \(byteLabel($0))" }
        var lines: [String] = []
        if post.logicalActionCompleted { lines.append("Moved to Trash") }
        if post.postMutationObservation.sourcePathState == .absent {
            lines.append("Original location verified")
        }
        if post.trashStillHoldingData, let moved {
            lines.append("\(moved.replacingOccurrences(of: "Moved to Trash: ", with: "")) remains in Trash")
        }

        let recoveryLabel: String
        switch post.storageRecoveryState {
        case .recoveryVerified:
            recoveryLabel = post.actualRecoveredBytes.map { "Disk recovery: \(byteLabel($0))" } ?? "Disk recovery verified"
        case .recoveryPending:
            recoveryLabel = "Disk recovery: Pending"
        default:
            recoveryLabel = "Disk recovery: Unknown"
        }

        return UIExecutionOutcome(
            entityID: post.entityID,
            action: post.action,
            readiness: readiness,
            logicalActionCompleted: post.logicalActionCompleted,
            storageRecoveryState: post.storageRecoveryState,
            recoveryLabel: recoveryLabel,
            potentialRecoveryLabel: potential,
            movedBytesLabel: moved,
            trashWarning: post.trashStillHoldingData
                ? "Other files may also be in your Trash. AI Storage Manager will not empty it automatically."
                : nil,
            userLines: lines,
            executionReport: report,
            postVerification: post,
            errorMessage: nil
        )
    }

    public static func surfaceReport(
        overview: StorageOverviewState,
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        selectedID: String?,
        preflight: UIPreflightResult?,
        approval: UIApprovalState?,
        execution: UIExecutionOutcome?
    ) -> UIActionSurfaceReport {
        UIActionSurfaceReport(
            generatedAt: Date(),
            candidateCount: safe.count + review.count + protected.count,
            safeActionCount: safe.count,
            reviewCount: review.count,
            protectedCount: protected.count,
            selectedCandidateID: selectedID,
            preflightState: preflight?.readiness.rawValue,
            approvalState: approval == nil ? nil : "APPROVED",
            executionState: execution?.readiness.rawValue,
            postVerificationState: execution?.postVerification?.verificationState.rawValue,
            recoveryState: execution?.storageRecoveryState.rawValue
        )
    }

    // MARK: - Internals

    private static func classifyGroup(item: ClassifiedItem, gate: MutationGateResult?) -> UICandidateGroup {
        if item.decision.safetyClass == .red { return .protected }
        if HardSafetyGates.isHardBlocked(path: item.detected.entity.path) { return .protected }
        if let gate, gate.executorImplemented,
           ActionExecutionPolicy.allowsFirstMutationTrash(entityID: item.detected.entity.id, path: item.detected.entity.path),
           [.approvalRequired, .contractSatisfiedReadOnly, .preflightRequired].contains(
               MutationReadiness(rawValue: gate.readiness) ?? .blocked
           ) {
            return .safeActions
        }
        if item.decision.safetyClass == .unknown || item.resolution.rawValue < ResolutionLevel.l5Actionable.rawValue {
            return .reviewNeeded
        }
        if item.decision.safetyClass == .yellow { return .reviewNeeded }
        if gate?.readiness == MutationReadiness.verifyMore.rawValue { return .reviewNeeded }
        if item.decision.safetyClass == .green { return .reviewNeeded }
        return .protected
    }

    private static func mapReadiness(
        gate: MutationGateResult?,
        safetyClass: SafetyClass,
        group: UICandidateGroup
    ) -> UIReadinessState {
        guard let gate else {
            return group == .protected ? .unknown : .verifyMore
        }
        return mapGateReadiness(gate.readiness)
    }

    private static func mapGateReadiness(_ raw: String) -> UIReadinessState {
        switch raw {
        case MutationReadiness.approvalRequired.rawValue: return .approvalRequired
        case MutationReadiness.preflightRequired.rawValue: return .preflightRequired
        case MutationReadiness.verifyMore.rawValue: return .verifyMore
        case MutationReadiness.contractSatisfiedReadOnly.rawValue: return .preflightRequired
        default: return .unknown
        }
    }

    private static func humanDisplayName(_ item: ClassifiedItem) -> String {
        if ActionPolicy.isDerivedData(item) { return "Xcode Derived Data" }
        return item.detected.entity.displayName.isEmpty
            ? item.detected.entity.subcategory
            : item.detected.entity.displayName
    }

    private static func humanCategory(_ item: ClassifiedItem) -> String {
        if ActionPolicy.isDerivedData(item) { return "Generated build data" }
        return item.detected.domain
    }

    private static func pathSummary(_ path: String) -> String {
        let components = (path as NSString).pathComponents
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        }
        return (path as NSString).lastPathComponent
    }

    private static func reasonSummary(_ item: ClassifiedItem, gate: MutationGateResult?) -> String {
        if ActionPolicy.isDerivedData(item) { return "Generated by Xcode; can be recreated" }
        if ActionPolicy.isOllamaStorage(item) {
            if let notes = item.verification?.vendorProofNotes,
               notes.contains(where: { $0.contains("VENDOR_ABSENT_MANAGED_DATA_REMAINS") }) {
                return "Ollama is not installed, but its managed model data remains. Restore Ollama management before cleanup — raw deletion is not offered."
            }
            if let notes = item.verification?.vendorProofNotes,
               notes.contains(where: { $0.contains("VENDOR_RESTORED_MODEL_UNRECOGNIZED") }) {
                return "Ollama management was restored, but the exact model was not recognized in the vendor inventory. Do not raw-delete or re-pull without further verification."
            }
            if let notes = item.verification?.vendorProofNotes,
               notes.contains(where: { $0.contains("OLLAMA_MANAGEMENT_RESTORED") }) {
                return "\(OllamaRestoreUXLabel.managementRestored). \(OllamaRestoreUXLabel.checkingSafety)"
            }
            if gate?.action == StorageAction.vendorNativeCleanup.rawValue,
               gate?.readiness == MutationReadiness.approvalRequired.rawValue {
                return "Recommended: Keep. Alternative verified action: Remove with Ollama (requires your approval). Raw deletion stays blocked."
            }
            if let notes = item.verification?.vendorProofNotes, notes.contains(where: { $0.contains("SHARED") }) {
                return "Some model files may be shared by multiple models. AI Storage Manager is checking those relationships."
            }
            return "Locally stored Ollama model data. Need to verify whether models can be downloaded again before recommending cleanup."
        }
        if ActionPolicy.isHuggingFaceStorage(item) {
            return "Locally stored AI model data. Need to verify whether these models can be downloaded again before recommending cleanup."
        }
        if let first = gate?.blockingReasons.first { return first.replacingOccurrences(of: "_", with: " ").capitalized }
        return item.decision.userExplanationJA
    }

    private static func evidenceLines(_ item: ClassifiedItem, gate: MutationGateResult?) -> [UIEvidenceLine] {
        var lines: [UIEvidenceLine] = []
        if let v = item.verification {
            if ActionPolicy.isAIVendorModelStorage(item) {
                lines.append(UIEvidenceLine(
                    id: "what", satisfied: true,
                    userText: "Installed/downloaded AI model storage.",
                    technicalDetail: "VENDOR_MODEL_STORAGE"
                ))
                if let unique = v.uniqueBytesProven {
                    lines.append(UIEvidenceLine(
                        id: "unique", satisfied: true,
                        userText: "Unique local storage: \(byteLabel(unique))",
                        technicalDetail: "UNIQUE_BYTES_VERIFIED"
                    ))
                }
                if let shared = v.sharedBytesProven {
                    lines.append(UIEvidenceLine(
                        id: "shared", satisfied: true,
                        userText: "Shared with other models/revisions: \(byteLabel(shared))",
                        technicalDetail: "SHARED_BYTES_VERIFIED"
                    ))
                }
                if v.referenceGraphConfidence == .verified {
                    lines.append(UIEvidenceLine(
                        id: "refs", satisfied: true,
                        userText: "Reference relationships were verified locally.",
                        technicalDetail: "REFERENCE_GRAPH_VERIFIED"
                    ))
                } else {
                    lines.append(UIEvidenceLine(
                        id: "refs", satisfied: false,
                        userText: "Reference relationships are still incomplete.",
                        technicalDetail: "REFERENCE_GRAPH_UNKNOWN"
                    ))
                }
                lines.append(UIEvidenceLine(
                    id: "reacq",
                    satisfied: v.reacquisition.confidence == .verified && v.reacquisition.value == .true,
                    userText: {
                        if let p = v.remoteReacquisitionProof {
                            switch p.status {
                            case .verified where p.isFresh:
                                return "Can be downloaded again: verified for exact remote identity."
                            case .verified:
                                return "Remote availability needs to be checked again."
                            case .authRequired:
                                return "Can be downloaded again? Auth required — not verified."
                            case .identityMismatch:
                                return "Exact remote revision/manifest no longer matches."
                            case .timeout, .rateLimited:
                                return "Can be downloaded again? Check incomplete (\(p.status.rawValue))."
                            default:
                                return "Can it be downloaded again? Not yet verified."
                            }
                        }
                        return "Can it be downloaded again? Not yet verified."
                    }(),
                    technicalDetail: v.reacquisition.reasonCode ?? "REACQUISITION_UNKNOWN"
                ))
                if let bytes = v.estimatedRedownloadBytes {
                    lines.append(UIEvidenceLine(
                        id: "redownload",
                        satisfied: true,
                        userText: "Removing this may require downloading up to \(byteLabel(bytes)) again.",
                        technicalDetail: "ESTIMATED_REDOWNLOAD_BYTES"
                    ))
                }
                if let p = v.remoteReacquisitionProof {
                    lines.append(UIEvidenceLine(
                        id: "remote_fresh",
                        satisfied: p.isFresh && p.status == .verified,
                        userText: p.isFresh
                            ? "Last remote check: fresh"
                            : "Remote availability needs to be checked again.",
                        technicalDetail: "AUTH_CLASS=\(p.authenticationClass.rawValue)"
                    ))
                }
                lines.append(UIEvidenceLine(
                    id: "runtime", satisfied: v.activeStateConfidence == .verified,
                    userText: v.activeStateConfidence == .verified
                        ? "Runtime state: \(v.activeState.rawValue.lowercased())"
                        : "Currently in use? Not proven from service process alone.",
                    technicalDetail: "RUNTIME_\(v.activeState.rawValue)_\(v.activeStateConfidence.rawValue)"
                ))
                lines.append(UIEvidenceLine(
                    id: "action", satisfied: false,
                    userText: "Correct action direction: vendor-native cleanup (not available in this version).",
                    technicalDetail: "VENDOR_NATIVE_CLEANUP_NOT_IMPLEMENTED"
                ))
            }
            if v.sourceOfTruth.value == .false, v.sourceOfTruth.confidence == .verified {
                lines.append(UIEvidenceLine(
                    id: "sot", satisfied: true,
                    userText: "Your original project exists elsewhere.",
                    technicalDetail: "SOT FALSE VERIFIED"
                ))
            }
            if v.regenerable.value == .true, v.regenerable.confidence == .verified {
                lines.append(UIEvidenceLine(
                    id: "regen", satisfied: true,
                    userText: "Xcode can regenerate this data.",
                    technicalDetail: "regenerable TRUE VERIFIED"
                ))
            }
            if v.activeState == .inactive, v.activeStateConfidence == .verified {
                lines.append(UIEvidenceLine(
                    id: "inactive", satisfied: true,
                    userText: "Xcode is not currently using this item.",
                    technicalDetail: "runtime INACTIVE VERIFIED"
                ))
            }
        }
        if let gate {
            for req in gate.satisfiedRequirements.prefix(4) {
                if lines.contains(where: { $0.technicalDetail == req }) { continue }
                lines.append(UIEvidenceLine(
                    id: req, satisfied: true,
                    userText: humanRequirement(req),
                    technicalDetail: req
                ))
            }
        }
        return lines
    }

    private static func preflightLines(
        from result: FreshReadOnlyPreflightEngine.RunResult,
        satisfied: Bool
    ) -> [UIEvidenceLine] {
        var lines: [UIEvidenceLine] = []
        let checks: [(String, Bool)] = [
            ("Item identity unchanged", result.bindingValid && result.sourceUnchanged),
            ("Original project exists", result.receipt.satisfiedClaims.contains(.sourceOfTruth) || result.sourceExists),
            ("Regenerable", !result.receipt.missingClaims.contains(.regenerability)),
            ("Xcode not running", !result.causalBlockerChain.contains(where: { $0.contains("xcode") || $0.contains("active") })),
            ("No open handles", !result.receipt.missingClaims.contains(where: { $0.rawValue.contains("OPEN") })),
        ]
        for (text, ok) in checks {
            if ok == satisfied {
                lines.append(UIEvidenceLine(id: text, satisfied: ok, userText: text, technicalDetail: nil))
            }
        }
        if !satisfied, let blocker = result.firstBlocker {
            lines.append(UIEvidenceLine(
                id: "blocker", satisfied: false,
                userText: blockingMessage(for: blocker),
                technicalDetail: blocker
            ))
        }
        return lines
    }

    private static func humanRequirement(_ req: String) -> String {
        switch req {
        case let s where s.contains("regenerable"): return "Xcode can regenerate this data."
        case let s where s.contains("source_of_truth"): return "Your original project exists elsewhere."
        case let s where s.contains("xcode_inactive"): return "Xcode is not currently using this item."
        case let s where s.contains("open_file"): return "No application has this item open."
        default: return req.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func blockingMessage(for blocker: String) -> String {
        if blocker.contains("xcode") || blocker.contains("active") || blocker.contains("SOURCE_ACTIVE") {
            return "Xcode is currently using this data"
        }
        if blocker.contains("open") { return "An application has this item open" }
        if blocker.contains("SOURCE_CHANGED") { return "This item changed since the scan" }
        return blocker.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func moveToTrashConsequence(for item: UICandidateItem) -> String {
        var parts = [
            "This item will be moved to the Trash.",
            "It will not be permanently deleted.",
            "Moving it to the Trash may not immediately free disk space.",
            "Disk space is generally reclaimed after the Trash is emptied.",
        ]
        if item.displayName.contains("Derived") || item.category.contains("Generated") {
            parts.append("Xcode can recreate this build data when needed.")
        }
        return parts.joined(separator: " ")
    }

    private static func recoverySemantics(for item: UICandidateItem) -> String {
        "Potential recovery: \(item.byteLabel). Actual disk recovery depends on Trash emptying and system behavior."
    }

    private static func mapHistory(
        _ report: ActionHistoryReport,
        closed: [PostMutationVerificationResult]
    ) -> [UIActionHistoryItem] {
        report.items.map { item in
            let closedResult = closed.first { $0.actionID == item.actionID }
            let recoveryPending = closedResult?.storageRecoveryState == .recoveryPending
                || item.storageRecoveryState == .recoveryPending
            var lines: [String] = []
            if item.logicalActionCompleted == true { lines.append("Action verified") }
            if recoveryPending { lines.append("Disk recovery pending") }
            if closedResult?.entityRegenerated == true { lines.append("Xcode regenerated new data") }

            let readiness: UIReadinessState
            if closedResult?.entityRegenerated == true { readiness = .regenerated }
            else if recoveryPending { readiness = .storageRecoveryPending }
            else if item.logicalActionCompleted == true { readiness = .completed }
            else if item.auditStatus == .failed { readiness = .failed }
            else { readiness = .postVerifyPending }

            return UIActionHistoryItem(
                id: item.actionID,
                timestamp: item.postVerifiedAt ?? item.executedAt ?? report.generatedAt,
                entityID: item.entityID,
                displayName: item.entityID.contains("deriveddata") ? "Xcode Derived Data" : item.entityID,
                action: item.action,
                actionLabel: "Moved to Trash",
                logicalVerified: item.logicalActionCompleted ?? false,
                storageRecoveryPending: recoveryPending,
                readiness: readiness,
                summaryLines: lines
            )
        }
    }

    public static func byteLabel(_ bytes: Int64) -> String {
        LocaleFormatting.byteLabel(bytes)
    }
}
