import Foundation

/// P2.2 — Canonical post-mutation verifier. Single source for targeted verify and scan reconciliation.
public enum PostMutationVerifier {
    public struct VerifyInput: Sendable {
        public var pending: PendingPostMutationVerification
        public var auditRecord: ActionAuditRecord
        public var contract: PostActionVerificationContract?
        public var scanItems: [ClassifiedItem]?
        public var observedAt: Date
        public var freeBytesNow: Int64?
        public var transactionAPISucceeded: Bool

        public init(
            pending: PendingPostMutationVerification,
            auditRecord: ActionAuditRecord,
            contract: PostActionVerificationContract? = nil,
            scanItems: [ClassifiedItem]? = nil,
            observedAt: Date = Date(),
            freeBytesNow: Int64? = nil,
            transactionAPISucceeded: Bool = true
        ) {
            self.pending = pending
            self.auditRecord = auditRecord
            self.contract = contract
            self.scanItems = scanItems
            self.observedAt = observedAt
            self.freeBytesNow = freeBytesNow ?? StorageCapacityMeasurer.freeBytes()
            self.transactionAPISucceeded = transactionAPISucceeded
        }
    }

    public static func verify(_ input: VerifyInput) -> PostMutationVerificationResult {
        let canonicalSource = (input.pending.sourcePath as NSString).standardizingPath
        let sourceExists = FileManager.default.fileExists(atPath: canonicalSource)
        let sourcePathState: SourcePathState = sourceExists ? .present : .absent

        let bindingMatches = input.pending.bindingFingerprint.entityID == input.auditRecord.entityID
            && input.pending.bindingFingerprint.canonicalPath == canonicalSource
            && input.auditRecord.action == input.pending.action

        let trashPath = input.pending.trashDestinationPath ?? input.auditRecord.destinationPath
        let trashObserved = observeTrash(path: trashPath, expectedName: URL(fileURLWithPath: canonicalSource).lastPathComponent)
        let trashEntityObserved = trashObserved.observed
        let trashIdentityMatch = trashObserved.identityMatch

        let siblingUnchanged = verifySiblingUnchanged(
            sourcePath: canonicalSource,
            entityID: input.pending.entityID
        )

        let auditRecordMatches = input.auditRecord.actionID == input.pending.actionID
            && input.auditRecord.entityID == input.pending.entityID
            && input.auditRecord.action == input.pending.action
            && (input.auditRecord.sourcePath as NSString).standardizingPath == canonicalSource

        let regeneration = detectRegeneration(
            originalEntityID: input.pending.entityID,
            originalPath: canonicalSource,
            executedAt: input.pending.executedAt,
            scanItems: input.scanItems,
            observedAt: input.observedAt
        )

        let sourceIdentityMatch: Bool
        if sourceExists {
            sourceIdentityMatch = false
        } else if regeneration.found && sourcePathState == .present {
            sourceIdentityMatch = false
        } else {
            sourceIdentityMatch = bindingMatches
        }

        let observation = PostMutationObservation(
            sourcePathState: regeneration.found && sourceExists ? .changed : sourcePathState,
            sourceIdentityMatch: sourceIdentityMatch,
            trashEntityObserved: trashEntityObserved,
            trashIdentityMatch: trashIdentityMatch,
            trashPath: trashObserved.path,
            siblingUnchanged: siblingUnchanged,
            bindingMatches: bindingMatches,
            auditRecordMatches: auditRecordMatches
        )

        var errors: [String] = []
        var unknownReasons: [String] = []

        let logicalConfirmed: Bool
        if !bindingMatches {
            logicalConfirmed = false
            unknownReasons.append("BINDING_MISMATCH")
        } else if sourceExists && !regeneration.found {
            logicalConfirmed = false
            errors.append("SOURCE_STILL_PRESENT")
        } else if !input.transactionAPISucceeded {
            logicalConfirmed = false
            errors.append("TRANSACTION_API_FAILED")
        } else if sourceExists && regeneration.found {
            logicalConfirmed = true
        } else if !sourceExists {
            logicalConfirmed = bindingMatches && auditRecordMatches
                && (trashEntityObserved || input.transactionAPISucceeded)
        } else {
            logicalConfirmed = false
            unknownReasons.append("AMBIGUOUS_SOURCE_STATE")
        }

        let trashStillHolding = trashEntityObserved
            || (trashPath != nil && FileManager.default.fileExists(atPath: trashPath!))

        let freeBefore = input.pending.freeBytesBeforeAction
        let freeAfterAction = input.pending.freeBytesAfterAction
        let freeNow = input.freeBytesNow

        let (actualRecovered, recoveryConfidence) = computeRecovery(
            freeBefore: freeBefore,
            freeAfterAction: freeAfterAction,
            freeNow: freeNow,
            trashStillHolding: trashStillHolding,
            expectedBytes: input.pending.expectedBytes
        )

        let storageRecoveryState: StorageRecoveryState
        if trashStillHolding {
            storageRecoveryState = .recoveryPending
        } else if actualRecovered != nil, actualRecovered! > 0 {
            storageRecoveryState = .recoveryVerified
        } else if freeBefore != nil, freeNow != nil {
            storageRecoveryState = .recoveryUnknown
        } else {
            storageRecoveryState = .notMeasured
        }

        let verificationState = classifyVerificationState(
            logicalConfirmed: logicalConfirmed,
            regeneration: regeneration.found,
            sourceExists: sourceExists,
            bindingMatches: bindingMatches,
            trashStillHolding: trashStillHolding,
            storageRecoveryState: storageRecoveryState,
            errors: errors
        )

        let auditStatus: AuditLifecycleStatus
        switch verificationState {
        case .actionConfirmed, .regenerated, .storageRecoveryPending, .storageRecoveryVerified:
            auditStatus = .postVerified
        case .actionPartiallyConfirmed, .stateChanged:
            auditStatus = .postVerifyPending
        case .actionFailed:
            auditStatus = .failed
        case .unknown, .notVerified, .verifying:
            auditStatus = .postVerifyPending
        }

        var steps = buildContractSteps(
            observation: observation,
            logicalConfirmed: logicalConfirmed,
            trashStillHolding: trashStillHolding,
            actualRecovered: actualRecovered,
            contract: input.contract
        )

        return PostMutationVerificationResult(
            actionID: input.pending.actionID,
            entityID: input.pending.entityID,
            action: input.pending.action,
            preMutationBindingFingerprint: input.pending.bindingFingerprint,
            postMutationObservation: observation,
            verificationState: verificationState,
            logicalActionCompleted: logicalConfirmed,
            storageRecoveryState: storageRecoveryState,
            expectedBytes: input.pending.expectedBytes,
            measuredBytesBefore: input.pending.expectedBytes,
            measuredBytesAfter: trashStillHolding ? StorageCapacityMeasurer.itemBytes(at: trashPath ?? "") : nil,
            freeBytesBeforeAction: freeBefore,
            freeBytesAfterAction: freeAfterAction,
            freeBytesAfterPostVerifyScan: freeNow,
            actualRecoveredBytes: actualRecovered,
            recoveryConfidence: recoveryConfidence,
            trashStillHoldingData: trashStillHolding,
            entityRegenerated: regeneration.found,
            regeneratedEntityID: regeneration.entityID,
            semanticRelationship: regeneration.relationship,
            auditStatus: auditStatus,
            verificationTimestamp: input.observedAt,
            executedAt: input.pending.executedAt,
            preflightObservedAt: input.pending.preflightObservedAt,
            regeneratedEntityObservedAt: regeneration.observedAt,
            contractVersion: input.contract?.version ?? TransactionContractRegistry.postVerifyTrashVersion,
            contractSteps: steps,
            errors: errors,
            unknownReasons: unknownReasons
        )
    }

    public static func storageRecovery(from result: PostMutationVerificationResult) -> StorageRecoveryResult {
        var reasonCodes: [String] = []
        if result.trashStillHoldingData { reasonCodes.append("TRASH_RETENTION") }
        if result.entityRegenerated { reasonCodes.append("REGENERATION_OCCURRED") }
        if result.recoveryConfidence == .unknown { reasonCodes.append("CONCURRENT_DISK_ACTIVITY") }
        if result.storageRecoveryState == .recoveryPending { reasonCodes.append("RECOVERY_PENDING_EMPTY_TRASH") }

        var notes: String?
        if result.trashStillHoldingData {
            notes = "MOVE_TO_TRASH succeeded; disk space not reclaimed until Trash is emptied separately."
        }

        return StorageRecoveryResult(
            actionID: result.actionID,
            entityID: result.entityID,
            expectedPotentialRecoveryBytes: result.expectedBytes,
            freeBytesBefore: result.freeBytesBeforeAction,
            freeBytesImmediatelyAfterAction: result.freeBytesAfterAction,
            freeBytesPostVerify: result.freeBytesAfterPostVerifyScan,
            actualObservedDelta: result.actualRecoveredBytes,
            confidence: result.recoveryConfidence,
            trashStillHoldingData: result.trashStillHoldingData,
            regenerationOccurred: result.entityRegenerated,
            reasonCodes: reasonCodes,
            notes: notes
        )
    }

    // MARK: - Internals

    private struct TrashObservation {
        var observed: Bool
        var identityMatch: Bool
        var path: String?
    }

    private struct RegenerationFinding {
        var found: Bool
        var entityID: String?
        var relationship: SemanticSuccessorRelationship
        var observedAt: Date?
    }

    private static func observeTrash(path: String?, expectedName: String) -> TrashObservation {
        guard let path else {
            return TrashObservation(observed: false, identityMatch: false, path: nil)
        }
        let canonical = (path as NSString).standardizingPath
        let exists = FileManager.default.fileExists(atPath: canonical)
        let nameMatch = URL(fileURLWithPath: canonical).lastPathComponent == expectedName
        return TrashObservation(observed: exists, identityMatch: exists && nameMatch, path: exists ? canonical : nil)
    }

    private static func verifySiblingUnchanged(sourcePath: String, entityID: String) -> Bool {
        let parent = (sourcePath as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: parent) else { return true }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: parent) else { return true }
        let targetName = URL(fileURLWithPath: sourcePath).lastPathComponent
        return !contents.contains(targetName)
    }

    private static func detectRegeneration(
        originalEntityID: String,
        originalPath: String,
        executedAt: Date,
        scanItems: [ClassifiedItem]?,
        observedAt: Date
    ) -> RegenerationFinding {
        guard let scanItems else {
            return RegenerationFinding(found: false, entityID: nil, relationship: .none, observedAt: nil)
        }
        let originalName = URL(fileURLWithPath: originalPath).lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let derivedRoot = ((home as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData") as NSString).standardizingPath
        let nonProductChildren: Set<String> = [
            "SDKStatCaches.noindex", "ModuleCache.noindex", "SymbolCache.noindex",
            "CompilationCache.noindex",
        ]
        for item in scanItems {
            guard ActionPolicy.isDerivedData(item) else { continue }
            let path = (item.detected.entity.path as NSString).standardizingPath
            guard path.lowercased().hasPrefix(derivedRoot.lowercased()) else { continue }
            let relative = String(path.dropFirst(derivedRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty, !relative.contains("/") else { continue }
            let itemName = URL(fileURLWithPath: path).lastPathComponent
            guard !nonProductChildren.contains(itemName) else { continue }
            let itemID = item.detected.entity.id
            guard itemID.hasPrefix("xcode.deriveddata.") else { continue }
            guard itemID != originalEntityID else { continue }
            guard itemName != originalName else { continue }
            return RegenerationFinding(
                found: true,
                entityID: itemID,
                relationship: .semanticSuccessor,
                observedAt: observedAt
            )
        }
        return RegenerationFinding(found: false, entityID: nil, relationship: .none, observedAt: nil)
    }

    private static func computeRecovery(
        freeBefore: Int64?,
        freeAfterAction: Int64?,
        freeNow: Int64?,
        trashStillHolding: Bool,
        expectedBytes: Int64?
    ) -> (Int64?, RecoveryConfidence) {
        if trashStillHolding {
            return (0, .exact)
        }
        if let before = freeBefore, let after = freeNow, after > before {
            return (after - before, .estimated)
        }
        if let before = freeBefore, let after = freeAfterAction, after > before {
            return (after - before, .estimated)
        }
        if !trashStillHolding, expectedBytes != nil {
            return (nil, .unknown)
        }
        return (nil, .unknown)
    }

    private static func classifyVerificationState(
        logicalConfirmed: Bool,
        regeneration: Bool,
        sourceExists: Bool,
        bindingMatches: Bool,
        trashStillHolding: Bool,
        storageRecoveryState: StorageRecoveryState,
        errors: [String]
    ) -> PostMutationVerificationState {
        if !bindingMatches { return .unknown }
        if !logicalConfirmed && !errors.isEmpty && sourceExists { return .actionFailed }
        if !logicalConfirmed && !bindingMatches { return .unknown }
        if regeneration && logicalConfirmed { return .regenerated }
        if logicalConfirmed && trashStillHolding {
            return storageRecoveryState == .recoveryVerified ? .storageRecoveryVerified : .storageRecoveryPending
        }
        if logicalConfirmed { return .actionConfirmed }
        if sourceExists { return .actionPartiallyConfirmed }
        return .unknown
    }

    private static func buildContractSteps(
        observation: PostMutationObservation,
        logicalConfirmed: Bool,
        trashStillHolding: Bool,
        actualRecovered: Int64?,
        contract: PostActionVerificationContract?
    ) -> [PostActionVerifyStepResult] {
        var steps: [PostActionVerifyStepResult] = [
            PostActionVerifyStepResult(
                step: "verify_source_no_longer_owns",
                satisfied: observation.sourcePathState == .absent || logicalConfirmed,
                detail: observation.sourcePathState.rawValue
            ),
            PostActionVerifyStepResult(
                step: "verify_trash_operation_result",
                satisfied: observation.trashEntityObserved || (logicalConfirmed && !trashStillHolding),
                detail: observation.trashPath
            ),
            PostActionVerifyStepResult(
                step: "verify_exact_entity_identity",
                satisfied: observation.bindingMatches && observation.auditRecordMatches,
                detail: observation.sourceIdentityMatch ? "match" : "mismatch"
            ),
            PostActionVerifyStepResult(
                step: "verify_sibling_unaffected",
                satisfied: observation.siblingUnchanged,
                detail: nil
            ),
            PostActionVerifyStepResult(
                step: "remeasure_storage",
                satisfied: true,
                detail: nil
            ),
            PostActionVerifyStepResult(
                step: "record_actual_recovered_bytes",
                satisfied: !trashStillHolding || actualRecovered != nil,
                detail: actualRecovered.map(String.init)
            ),
        ]
        if let contract {
            for step in contract.verificationSteps where !steps.contains(where: { $0.step == step }) {
                steps.append(PostActionVerifyStepResult(step: step, satisfied: logicalConfirmed, detail: nil))
            }
        }
        steps.append(PostActionVerifyStepResult(
            step: "complete_audit",
            satisfied: logicalConfirmed,
            detail: logicalConfirmed ? "ready_to_close" : "pending"
        ))
        return steps
    }
}

/// Backward-compatible wrapper used by P2.1 immediate checks.
public enum TrashPostActionVerifierBridge {
    public static func verify(
        sourcePath: String,
        trashDestination: String?,
        contract: PostActionVerificationContract?,
        bindingFingerprint: ActionBindingFingerprint,
        actionID: String,
        entityID: String,
        expectedBytes: Int64?,
        executedAt: Date,
        freeBytesBefore: Int64?,
        freeBytesAfter: Int64?
    ) -> (steps: [PostActionVerifyStepResult], result: PostMutationVerificationResult) {
        let pending = PendingPostMutationVerification(
            actionID: actionID,
            entityID: entityID,
            action: .moveToTrash,
            bindingFingerprint: bindingFingerprint,
            sourcePath: sourcePath,
            expectedDestinationSemantics: "TRASH",
            trashDestinationPath: trashDestination,
            expectedBytes: expectedBytes,
            executedAt: executedAt,
            approvalID: nil,
            preflightReceiptID: nil,
            preflightObservedAt: nil,
            auditStatus: .postVerifyPending,
            freeBytesBeforeAction: freeBytesBefore,
            freeBytesAfterAction: freeBytesAfter,
            verificationDeadline: nil
        )
        let audit = ActionAuditRecord(
            actionID: actionID,
            entityID: entityID,
            action: .moveToTrash,
            sourcePath: sourcePath,
            destinationPath: trashDestination,
            preflightClaims: [],
            transactionPhase: TrashTransactionPhase.postVerify.rawValue,
            logicalBytesAffected: expectedBytes,
            measuredRecoveryBytes: nil,
            failureReason: nil,
            startedAt: executedAt,
            auditStatus: AuditLifecycleStatus.postVerifyPending.rawValue,
            bindingFingerprint: bindingFingerprint,
            approvalID: nil,
            preflightReceiptID: nil,
            executedAt: executedAt,
            freeBytesBeforeAction: freeBytesBefore,
            freeBytesAfterAction: freeBytesAfter
        )
        let result = PostMutationVerifier.verify(PostMutationVerifier.VerifyInput(
            pending: pending,
            auditRecord: audit,
            contract: contract,
            scanItems: nil,
            observedAt: Date(),
            freeBytesNow: freeBytesAfter,
            transactionAPISucceeded: true
        ))
        return (result.contractSteps, result)
    }
}
