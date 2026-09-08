import Foundation

/// P2.2 — Read-only persisted pending post-mutation verification registry.
public enum PendingPostMutationRegistry {
    public static let registryFileName = "pending_post_mutation_verifications.json"
    public static let executionReportFileName = "p2_1_first_mutation_execution.json"

    public static func load(from directory: URL) -> PendingPostMutationRegistryDocument {
        let registryURL = directory.appendingPathComponent(registryFileName)
        if let data = try? Data(contentsOf: registryURL),
           let decoded = try? JSONDecoder.iso8601.decode(PendingPostMutationRegistryDocument.self, from: data) {
            return decoded
        }
        if let bootstrapped = bootstrapFromExecutionReport(directory: directory) {
            return PendingPostMutationRegistryDocument(pending: [bootstrapped], closed: [])
        }
        return .empty
    }

    public static func save(_ registry: PendingPostMutationRegistryDocument, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(registryFileName)
        let data = try JSONEncoder.iso8601.encode(registry)
        try data.write(to: url)
    }

    public static func registerPending(
        _ pending: PendingPostMutationVerification,
        in directory: URL
    ) throws -> PendingPostMutationRegistryDocument {
        var registry = load(from: directory)
        registry.pending.removeAll { $0.actionID == pending.actionID }
        registry.pending.append(pending)
        try save(registry, to: directory)
        return registry
    }

    public static func reconcile(
        registry: PendingPostMutationRegistryDocument,
        scanItems: [ClassifiedItem],
        registryDirectory: URL? = nil,
        observedAt: Date = Date()
    ) -> PendingPostMutationRegistryDocument {
        var updated = registry
        var queue = updated.pending
        if queue.isEmpty, let dir = registryDirectory,
           let bootstrapped = bootstrapFromExecutionReport(directory: dir) {
            queue = [bootstrapped]
        }
        var stillPending: [PendingPostMutationVerification] = []
        var newClosed: [PostMutationVerificationResult] = []
        for pending in queue {
            let audit = auditRecord(from: pending)
            let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
                pending: pending,
                auditRecord: audit,
                contract: TransactionContractRegistry.postVerifyContract(for: pending.action, item: syntheticItem(from: pending)),
                scanItems: scanItems,
                observedAt: observedAt
            ))
            if result.auditStatus == .postVerified || result.auditStatus == .failed {
                newClosed.append(result)
            } else {
                stillPending.append(pending)
            }
        }
        for closed in updated.closed where !newClosed.contains(where: { $0.actionID == closed.actionID }) {
            newClosed.append(closed)
        }
        updated.pending = stillPending
        updated.closed = newClosed
        return updated
    }

    public static func buildActionHistory(
        registry: PendingPostMutationRegistryDocument,
        executionReport: ActFirstMutationExecutionReport?
    ) -> ActionHistoryReport {
        var items: [ActionHistoryItem] = []
        if let exec = executionReport, let audit = exec.auditRecord {
            let closed = registry.closed.first { $0.actionID == exec.permitID ?? audit.actionID }
            items.append(ActionHistoryItem(
                actionID: audit.actionID,
                entityID: exec.entityID,
                action: .moveToTrash,
                sourcePath: exec.path,
                plannedAt: nil,
                preflightedAt: nil,
                approvedAt: nil,
                executedAt: audit.executedAt ?? audit.startedAt,
                postVerifiedAt: closed?.verificationTimestamp,
                auditStatus: closed?.auditStatus ?? .postVerifyPending,
                verificationState: closed?.verificationState,
                logicalActionCompleted: closed?.logicalActionCompleted,
                storageRecoveryState: closed?.storageRecoveryState,
                approvalID: exec.approvalID,
                permitID: exec.permitID
            ))
        }
        for closed in registry.closed where !items.contains(where: { $0.actionID == closed.actionID }) {
            items.append(ActionHistoryItem(
                actionID: closed.actionID,
                entityID: closed.entityID,
                action: closed.action,
                sourcePath: closed.preMutationBindingFingerprint.canonicalPath,
                plannedAt: nil,
                preflightedAt: closed.preflightObservedAt,
                approvedAt: nil,
                executedAt: closed.executedAt,
                postVerifiedAt: closed.verificationTimestamp,
                auditStatus: closed.auditStatus,
                verificationState: closed.verificationState,
                logicalActionCompleted: closed.logicalActionCompleted,
                storageRecoveryState: closed.storageRecoveryState,
                approvalID: nil,
                permitID: closed.actionID
            ))
        }
        for pending in registry.pending where !items.contains(where: { $0.actionID == pending.actionID }) {
            items.append(ActionHistoryItem(
                actionID: pending.actionID,
                entityID: pending.entityID,
                action: pending.action,
                sourcePath: pending.sourcePath,
                plannedAt: nil,
                preflightedAt: pending.preflightObservedAt,
                approvedAt: nil,
                executedAt: pending.executedAt,
                postVerifiedAt: nil,
                auditStatus: pending.auditStatus,
                verificationState: nil,
                logicalActionCompleted: nil,
                storageRecoveryState: nil,
                approvalID: pending.approvalID,
                permitID: pending.actionID
            ))
        }
        items.sort { ($0.executedAt ?? .distantPast) < ($1.executedAt ?? .distantPast) }
        return ActionHistoryReport(items: items, generatedAt: Date())
    }

    public static func bootstrapFromExecutionReport(directory: URL) -> PendingPostMutationVerification? {
        let url = directory.appendingPathComponent(executionReportFileName)
        guard let data = try? Data(contentsOf: url),
              let exec = try? JSONDecoder.iso8601.decode(ActFirstMutationExecutionReport.self, from: data),
              let audit = exec.auditRecord else { return nil }
        let fp = ActionBindingFingerprint(
            entityID: exec.entityID,
            action: .moveToTrash,
            canonicalPath: exec.path,
            evidenceGeneration: 1,
            verificationGeneration: 1,
            runtimeGeneration: 1,
            ruleVersion: "P2.1",
            transactionContractVersion: TransactionContractRegistry.trashVersion
        )
        return PendingPostMutationVerification(
            actionID: audit.actionID,
            entityID: exec.entityID,
            action: .moveToTrash,
            bindingFingerprint: fp,
            sourcePath: exec.path,
            expectedDestinationSemantics: "TRASH",
            trashDestinationPath: exec.trashDestinationPath,
            expectedBytes: audit.logicalBytesAffected,
            executedAt: audit.startedAt,
            approvalID: exec.approvalID,
            preflightReceiptID: exec.preflightSessionID,
            preflightObservedAt: nil,
            auditStatus: .postVerifyPending,
            freeBytesBeforeAction: audit.freeBytesBeforeAction,
            freeBytesAfterAction: audit.freeBytesAfterAction,
            verificationDeadline: nil
        )
    }

    public static func loadExecutionReport(from directory: URL) -> ActFirstMutationExecutionReport? {
        let url = directory.appendingPathComponent(executionReportFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso8601.decode(ActFirstMutationExecutionReport.self, from: data)
    }

    private static func auditRecord(from pending: PendingPostMutationVerification) -> ActionAuditRecord {
        ActionAuditRecord(
            actionID: pending.actionID,
            entityID: pending.entityID,
            action: pending.action,
            sourcePath: pending.sourcePath,
            destinationPath: pending.trashDestinationPath,
            preflightClaims: [],
            transactionPhase: TrashTransactionPhase.postVerify.rawValue,
            logicalBytesAffected: pending.expectedBytes,
            measuredRecoveryBytes: nil,
            failureReason: nil,
            startedAt: pending.executedAt,
            auditStatus: pending.auditStatus.rawValue,
            bindingFingerprint: pending.bindingFingerprint,
            approvalID: pending.approvalID,
            preflightReceiptID: pending.preflightReceiptID,
            executedAt: pending.executedAt,
            freeBytesBeforeAction: pending.freeBytesBeforeAction,
            freeBytesAfterAction: pending.freeBytesAfterAction
        )
    }

    private static func syntheticItem(from pending: PendingPostMutationVerification) -> ClassifiedItem {
        let entity = StorageEntity(
            id: pending.entityID,
            kind: .generatedBuild,
            category: "DEV",
            subcategory: "XCODE",
            displayName: pending.entityID,
            path: pending.sourcePath,
            logicalBytes: pending.expectedBytes ?? 0
        )
        let decision = SafetyDecision(
            entity: entity,
            action: .moveToTrash,
            safetyClass: .green,
            safetyScore: SafetyScore(value: 95),
            reasonCodes: ["GENERATED_DATA"],
            sideEffects: [],
            matchedRuleID: "post_mutation_verify",
            evaluationLayer: .exactVendor,
            evidenceConfidence: 0.95,
            userExplanationJA: "DerivedData",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: DetectedEntity(
                entity: entity,
                bucket: .generated,
                domain: "Developer",
                associatedProcesses: ["Xcode"],
                identified: true,
                annotation: nil
            ),
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: pending.expectedBytes ?? 0,
            actionVariants: [:],
            inclusiveBytes: pending.expectedBytes ?? 0,
            exclusiveBytes: pending.expectedBytes ?? 0,
            resolution: .l5Actionable,
            verification: nil
        )
    }

    public static func formatScanSummary(results: [PostMutationVerificationResult], pending: [PendingPostMutationVerification]) -> PostMutationScanSummary {
        var lines: [String] = ["Post-action verification:"]
        if results.isEmpty && pending.isEmpty {
            lines.append("  (no prior actions to verify)")
            return PostMutationScanSummary(lines: lines, hasPendingVerification: false)
        }
        for result in results {
            lines.append("")
            lines.append("  \(result.action.rawValue)")
            lines.append("  \(result.preMutationBindingFingerprint.canonicalPath)")
            if result.logicalActionCompleted {
                lines.append("  ✓ Original entity moved successfully")
            } else {
                lines.append("  ✗ Logical action not confirmed")
            }
            if result.postMutationObservation.sourcePathState == .absent {
                lines.append("  ✓ Source no longer contains original entity")
            } else if result.entityRegenerated {
                lines.append("  ✓ Original action confirmed; new entity regenerated")
                if let regen = result.regeneratedEntityID {
                    lines.append("  New generated entity: \(regen)")
                }
            } else {
                lines.append("  ⚠ Source state: \(result.postMutationObservation.sourcePathState.rawValue)")
            }
            if result.trashStillHoldingData {
                lines.append("  ⚠ Trash still contains data")
                lines.append("  ⚠ Disk recovery pending until Trash is emptied")
            } else if result.storageRecoveryState == .recoveryVerified {
                lines.append("  ✓ Storage recovery verified")
            }
        }
        for p in pending where !results.contains(where: { $0.actionID == p.actionID }) {
            lines.append("")
            lines.append("  \(p.action.rawValue) — POST_VERIFY_PENDING")
            lines.append("  \(p.sourcePath)")
        }
        return PostMutationScanSummary(lines: lines, hasPendingVerification: !pending.isEmpty)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
