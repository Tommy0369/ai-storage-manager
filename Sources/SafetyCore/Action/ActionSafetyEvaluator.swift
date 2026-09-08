import Foundation

/// Action-specific Safety gates. Entity × Action × State. Does NOT execute.
public enum ActionSafetyEvaluator {
    public static func evaluateAll(
        item: ClassifiedItem,
        engine: SafetyRuleEngine,
        evidence: EvidenceBundle,
        state: RuntimeState,
        userContext: ActionUserContext = .default,
        snapshot: EntitySafetySnapshot? = nil,
        safetyDecisions: [ActionMode: SafetyDecision]? = nil
    ) -> [StorageAction: ActionDecision] {
        let resolvedEvidence = snapshot?.evidence ?? evidence
        let resolvedState = snapshot?.state ?? state
        var map: [StorageAction: ActionDecision] = [:]
        for action in StorageAction.allCases {
            map[action] = evaluate(
                item: item,
                action: action,
                engine: engine,
                evidence: resolvedEvidence,
                state: resolvedState,
                userContext: userContext,
                snapshot: snapshot,
                safetyDecisions: safetyDecisions
            )
        }
        return map
    }

    public static func evaluate(
        item: ClassifiedItem,
        action: StorageAction,
        engine: SafetyRuleEngine,
        evidence: EvidenceBundle,
        state: RuntimeState,
        userContext: ActionUserContext = .default,
        snapshot: EntitySafetySnapshot? = nil,
        safetyDecisions: [ActionMode: SafetyDecision]? = nil
    ) -> ActionDecision {
        let id = item.detected.entity.id
        let bytes = item.exclusiveBytes
        let v = item.verification

        switch action {
        case .keep:
            return ActionDecision(
                entityID: id,
                action: .keep,
                safetyClass: item.decision.safetyClass,
                eligible: true,
                explanationCodes: ["KEEP_ALWAYS_ALLOWED"]
            )

        case .moveToTrash:
            return evaluateMoveToTrash(
                item: item,
                engine: engine,
                evidence: evidence,
                state: state,
                bytes: bytes,
                v: v,
                snapshot: snapshot,
                safetyDecisions: safetyDecisions
            )

        case .moveToICloud:
            return evaluateMoveToICloud(item: item, evidence: evidence, state: state, bytes: bytes, v: v, userContext: userContext)

        case .removeLocalDownload:
            return evaluateRemoveLocalDownload(
                item: item,
                engine: engine,
                evidence: evidence,
                state: state,
                bytes: bytes,
                v: v,
                safetyDecisions: safetyDecisions
            )

        case .vendorNativeCleanup:
            return evaluateVendorCleanup(item: item, engine: engine, evidence: evidence, state: state, bytes: bytes)
        }
    }

    static func evaluateMoveToTrash(
        item: ClassifiedItem,
        engine: SafetyRuleEngine,
        evidence: EvidenceBundle,
        state: RuntimeState,
        bytes: Int64,
        v: VerificationAnnotation?,
        snapshot: EntitySafetySnapshot? = nil,
        safetyDecisions: [ActionMode: SafetyDecision]? = nil
    ) -> ActionDecision {
        let id = item.detected.entity.id
        var blocked: [ActionBlockReason] = []
        var missing: [ClaimType] = []

        if ActionPolicy.isVoiceMemo(item) {
            blocked.append(.voiceMemoNativeSyncRequired)
        }
        if ActionPolicy.isIOSBackup(item) {
            blocked.append(.iosBackupRequiresDeviceAwareMigration)
        }
        if ActionPolicy.isClaudeRuntime(item) {
            blocked.append(.applicationManagedData)
        }
        if ActionPolicy.isAIVendorModelStorage(item) || ActionPolicy.isRawAIVendorBlob(item) {
            // Prefer vendor-native cleanup. Shared/raw blobs never auto-promote to trash.
            blocked.append(.applicationManagedData)
            if item.verification?.referenceGraphConfidence != .verified {
                missing.append(.referenceGraph)
            }
            missing.append(.reacquisition)
        }

        let trashDecision = safetyDecisions?[.moveToTrash] ?? engine.evaluate(EvaluationRequest(
            entity: item.detected.entity,
            intendedAction: .moveToTrash,
            evidence: evidence,
            state: state
        ))

        if trashDecision.safetyClass == .red { blocked.append(.safetyClassRed) }
        if item.decision.safetyClass == .red { blocked.append(.safetyClassRed) }
        let provenDerivedDataTrash = ActionPolicy.isDerivedData(item)
            && v?.sourceOfTruth.value == .false && v?.sourceOfTruth.confidence == .verified
            && v?.regenerable.value == .true && v?.regenerable.confidence == .verified
            && !(v?.activeState == .active && v?.activeStateConfidence == .verified)
            && trashDecision.safetyClass != .red
            && item.decision.safetyClass != .red
        if trashDecision.safetyClass == .unknown, !provenDerivedDataTrash {
            blocked.append(.safetyClassUnknown)
        }

        if v?.activeState == .active, v?.activeStateConfidence == .verified {
            blocked.append(.sourceActive)
        }
        let openFileVerifiedSafe = evidence.openFileHandle == .false
            || evidence.predicateConfidence["no_open_file_handle"] == .verified
            || snapshot?.predicates.openFileConfidence == .verified
        if evidence.openFileHandle == .true {
            blocked.append(.sourceOpen)
        } else if evidence.openFileHandle == .unknown, !openFileVerifiedSafe {
            missing.append(.openFileState)
            blocked.append(.verificationIncomplete)
        }

        // MOVE_TO_TRASH: SOT FALSE verified required for generated/disposable contract
        let greenDerivedDataTrash = item.decision.safetyClass == .green
            && ActionPolicy.isDerivedData(item)
            && v?.sourceOfTruth.value == .false && v?.sourceOfTruth.confidence == .verified
            && v?.regenerable.value == .true && v?.regenerable.confidence == .verified
            && evidence.openFileHandle != .true
        if ActionPolicy.isDerivedData(item) || item.detected.annotation?.lifecycle.role == .generatedArtifact
            || item.detected.annotation?.lifecycle.role == .cache {
            if v?.sourceOfTruth.value != .false || v?.sourceOfTruth.confidence != .verified {
                if v?.sourceOfTruth.confidence != .verified { missing.append(.sourceOfTruth) }
                blocked.append(.sourceOfTruthUnknown)
            }
            if v?.regenerable.value != .true || v?.regenerable.confidence != .verified {
                if v?.regenerable.confidence != .verified { missing.append(.regenerability) }
                blocked.append(.regenerabilityUnknown)
            }
        }

        if evidence.canonicalPath.isEmpty {
            missing.append(.canonicalPath)
            blocked.append(.verificationIncomplete)
        }

        let trashEligibleByEngine = trashDecision.safetyClass == .green || trashDecision.safetyClass == .yellow
        let eligible = blocked.isEmpty && (trashEligibleByEngine || provenDerivedDataTrash || greenDerivedDataTrash)
        let effectiveClass: SafetyClass
        if (provenDerivedDataTrash || greenDerivedDataTrash) && trashDecision.safetyClass == .unknown {
            effectiveClass = .green
        } else {
            effectiveClass = trashDecision.safetyClass
        }
        return ActionDecision(
            entityID: id,
            action: .moveToTrash,
            safetyClass: effectiveClass,
            eligible: eligible,
            requiredClaims: [
                ClaimRequirement(claimType: .sourceOfTruth, requiredPredicate: .false),
                ClaimRequirement(claimType: .regenerability, requiredPredicate: .true, freshness: .runtimeFresh),
                ClaimRequirement(claimType: .openFileState, requiredPredicate: .false, freshness: .runtimeFresh),
            ],
            satisfiedClaimTypes: eligible ? [.canonicalPath, .sourceOfTruth, .regenerability, .openFileState] : [],
            missingClaimTypes: missing,
            blockedReasons: dedupe(blocked),
            expectedLocalRecoveryBytes: eligible ? bytes : nil,
            recoveryConfidence: eligible ? .verified : .unknown,
            explanationCodes: trashDecision.reasonCodes
        )
    }

    static func evaluateMoveToICloud(
        item: ClassifiedItem,
        evidence: EvidenceBundle,
        state: RuntimeState,
        bytes: Int64,
        v: VerificationAnnotation?,
        userContext: ActionUserContext
    ) -> ActionDecision {
        let id = item.detected.entity.id
        var blocked: [ActionBlockReason] = []
        var missing: [ClaimType] = []
        var satisfied: [ClaimType] = []

        // CRITICAL: SOT TRUE is ALLOWED for MOVE_TO_ICLOUD — preservation action
        if ActionPolicy.isVoiceMemo(item) {
            blocked.append(.voiceMemoNativeSyncRequired)
        }
        if ActionPolicy.isIOSBackup(item) {
            blocked.append(.iosBackupRequiresDeviceAwareMigration)
        }
        if ActionPolicy.isClaudeRuntime(item) {
            blocked.append(.applicationManagedData)
        }
        if ActionPolicy.isDerivedData(item) {
            blocked.append(.applicationManagedData)
            blocked.append(.relocationContractMissing)
        }
        if ActionPolicy.isGitRepository(item) {
            blocked.append(.relocationContractMissing)
            blocked.append(.applicationManagedData)
        }
        if ActionPolicy.isLibraryManagedPath(item.detected.entity.path) {
            blocked.append(.relocationContractMissing)
            blocked.append(.applicationManagedData)
        }

        let userOwned = ActionPolicy.userOwnedVerified(item)
        if userOwned { satisfied.append(.userOwned) }
        else { missing.append(.userOwned); blocked.append(.relocationContractMissing) }

        if !evidence.canonicalPath.isEmpty { satisfied.append(.canonicalPath) }
        else { missing.append(.canonicalPath); blocked.append(.verificationIncomplete) }

        if v?.activeState == .active, v?.activeStateConfidence == .verified {
            blocked.append(.sourceActive)
        }
        if evidence.openFileHandle == .true { blocked.append(.sourceOpen) }

        if userContext.iCloudEnabled == false {
            blocked.append(.iCloudUnavailable)
        } else if userContext.iCloudEnabled == nil {
            missing.append(.iCloudAvailable)
        } else {
            satisfied.append(.iCloudAvailable)
        }

        // Preservation contract: SOT may be TRUE verified — do NOT block on SOT TRUE
        if userOwned, v?.sourceOfTruth.value == .true, v?.sourceOfTruth.confidence == .verified {
            satisfied.append(.preservationContract)
        } else if userOwned, ActionPolicy.isUserOwnedRoot(item.detected.entity.path) {
            satisfied.append(.preservationContract)
        } else if !blocked.contains(.relocationContractMissing) {
            missing.append(.preservationContract)
        }

        let eligible = blocked.isEmpty && !missing.contains(.userOwned)
        return ActionDecision(
            entityID: id,
            action: .moveToICloud,
            safetyClass: eligible ? .green : .yellow,
            eligible: eligible,
            requiredClaims: [
                ClaimRequirement(claimType: .userOwned),
                ClaimRequirement(claimType: .canonicalPath),
                ClaimRequirement(claimType: .preservationContract),
                ClaimRequirement(claimType: .iCloudAvailable),
            ],
            satisfiedClaimTypes: satisfied,
            missingClaimTypes: missing,
            blockedReasons: dedupe(blocked),
            expectedLocalRecoveryBytes: 0,
            expectedLogicalBytesMoved: bytes,
            recoveryConfidence: .unknown,
            explanationCodes: eligible ? ["PRESERVATION_TRANSACTION", "SOT_TRUE_ALLOWED"] : blocked.map(\.rawValue)
        )
    }

    static func dedupe(_ blocked: [ActionBlockReason]) -> [ActionBlockReason] {
        blocked.reduce(into: [ActionBlockReason]()) { arr, reason in
            if !arr.contains(reason) { arr.append(reason) }
        }
    }

    static func evaluateRemoveLocalDownload(
        item: ClassifiedItem,
        engine: SafetyRuleEngine,
        evidence: EvidenceBundle,
        state: RuntimeState,
        bytes: Int64,
        v: VerificationAnnotation?,
        safetyDecisions: [ActionMode: SafetyDecision]? = nil
    ) -> ActionDecision {
        let id = item.detected.entity.id
        var blocked: [ActionBlockReason] = []
        var missing: [ClaimType] = []

        if ActionPolicy.isVoiceMemo(item) { blocked.append(.voiceMemoNativeSyncRequired) }
        if ActionPolicy.isIOSBackup(item) { blocked.append(.iosBackupRequiresDeviceAwareMigration) }

        if !ActionPolicy.fileProviderBacked(item, evidence: evidence) {
            blocked.append(.fileProviderRequired)
            missing.append(.fileProviderBacked)
        }

        if evidence.syncWouldDeleteRemote == .unknown || evidence.iCloudEvictable == .unknown {
            blocked.append(.syncStateUnknown)
            missing.append(.syncSafe)
        }

        let hasVerifiedRel = (item.detected.annotation?.relationships ?? []).contains { $0.confidence == .verified }
        if !hasVerifiedRel, evidence.cloudFileProvider != .true {
            blocked.append(.remoteCopyUnknown)
            missing.append(.remoteBacking)
        }

        let evictDecision = safetyDecisions?[.cloudEvictOnly] ?? engine.evaluate(EvaluationRequest(
            entity: item.detected.entity,
            intendedAction: .cloudEvictOnly,
            evidence: evidence,
            state: state
        ))

        if evictDecision.safetyClass == .red { blocked.append(.safetyClassRed) }
        if evictDecision.safetyClass == .unknown { blocked.append(.safetyClassUnknown) }

        let eligible = blocked.isEmpty && evictDecision.safetyClass != .red
        return ActionDecision(
            entityID: id,
            action: .removeLocalDownload,
            safetyClass: evictDecision.safetyClass,
            eligible: eligible,
            requiredClaims: [
                ClaimRequirement(claimType: .fileProviderBacked),
                ClaimRequirement(claimType: .remoteBacking, freshness: .cloudFresh),
                ClaimRequirement(claimType: .syncSafe, freshness: .cloudFresh),
            ],
            missingClaimTypes: missing,
            blockedReasons: blocked,
            expectedLocalRecoveryBytes: eligible ? bytes : nil,
            recoveryConfidence: eligible ? .verified : .unknown,
            explanationCodes: ["REMOVE_LOCAL_DOWNLOAD_NOT_DELETE"]
        )
    }

    static func evaluateVendorCleanup(
        item: ClassifiedItem,
        engine: SafetyRuleEngine,
        evidence: EvidenceBundle,
        state: RuntimeState,
        bytes: Int64
    ) -> ActionDecision {
        _ = engine
        _ = evidence
        _ = state
        let id = item.detected.entity.id
        var blocked: [ActionBlockReason] = []
        var missing: [ClaimType] = []
        let v = item.verification

        if ActionPolicy.isAIVendorModelStorage(item) {
            if ActionPolicy.isRawAIVendorBlob(item) {
                blocked.append(.notApplicable)
                blocked.append(.applicationManagedData)
            }
            if v?.referenceGraphConfidence != .verified {
                missing.append(.referenceGraph)
                blocked.append(.verificationIncomplete)
            }
            let remote = v?.remoteReacquisitionProof
            let reacqFreshVerified = (remote?.isStrictVerified == true)
                || (v?.reacquisition.confidence == .verified
                    && v?.reacquisition.value == .true
                    && (remote == nil || remote?.isFresh == true))
            if !reacqFreshVerified {
                missing.append(.reacquisition)
                // Contract requires REACQUIRABILITY, not REGENERABILITY.
                blocked.append(.reacquisitionNotStrictVerified)
            }
            if v?.activeState == .active, v?.activeStateConfidence == .verified {
                blocked.append(.sourceActive)
            }
            // Entity RED means "do not trash / unprotected delete".
            // Vendor-native cleanup is the authorized route for application-managed vendor data —
            // do not inherit KEEP/trash RED into vendor-native eligibility.
            if item.decision.safetyClass == .red,
               !ActionPolicy.isAIVendorModelStorage(item) {
                blocked.append(.safetyClassRed)
            }
            if v?.vendorProofNotes.contains(where: { $0.contains("USER_ORIGINAL") || $0.contains("CUSTOM") }) == true {
                blocked.append(.userOriginalRequiresPreservation)
            }
            // Do NOT promote SafetyClass to GREEN — action eligibility is separate.
            // Action-specific safetyClass stays UNKNOWN as a presentation token, not "bypass".
            // Canonical eligibility is `eligible` + strict predicates, never GREEN shortcut.
            let eligible = blocked.isEmpty && reacqFreshVerified && v?.referenceGraphConfidence == .verified
            var explanations = [
                "VENDOR_NATIVE_CLEANUP_PREFERRED",
                "MOVE_TO_TRASH_NOT_SELECTED_FOR_VENDOR_CACHE",
                "ACTION_SPECIFIC_DECISION_NOT_GENERIC_ENTITY_CLASS",
                "REACQUIRABILITY_REQUIRED_REGENERABILITY_NOT_REQUIRED"
            ]
            if reacqFreshVerified {
                explanations.append("REMOTE_REACQUISITION_VERIFIED")
                if let bytes = v?.estimatedRedownloadBytes ?? v?.uniqueBytesProven {
                    explanations.append("ESTIMATED_REDOWNLOAD_BYTES=\(bytes)")
                }
            } else {
                explanations.append("REACQUISITION_NOT_VERIFIED")
            }
            return ActionDecision(
                entityID: id,
                action: .vendorNativeCleanup,
                safetyClass: .unknown,
                eligible: eligible,
                requiredClaims: [
                    ClaimRequirement(claimType: .vendorOwnership, freshness: .staticClaim),
                    ClaimRequirement(claimType: .referenceGraph, freshness: .staticClaim),
                    ClaimRequirement(claimType: .reacquisition, freshness: .remoteStateFresh),
                    ClaimRequirement(claimType: .activeState, requiredPredicate: .false, freshness: .runtimeFresh)
                ],
                missingClaimTypes: missing,
                blockedReasons: blocked,
                expectedLocalRecoveryBytes: eligible ? (v?.uniqueBytesProven ?? bytes) : v?.uniqueBytesProven,
                expectedLogicalBytesMoved: eligible ? (v?.uniqueBytesProven ?? bytes) : nil,
                recoveryConfidence: eligible ? .verified : .unknown,
                explanationCodes: explanations
            )
        }

        let mode = item.decision.action
        let supported = mode == .toolCLIOnly || mode == .packageManagerCommand || mode == .appAPIOnly
        let eligible = supported && item.decision.safetyClass == .green
        return ActionDecision(
            entityID: id,
            action: .vendorNativeCleanup,
            safetyClass: item.decision.safetyClass,
            eligible: eligible,
            blockedReasons: supported ? [] : [.notApplicable],
            expectedLocalRecoveryBytes: eligible ? bytes : nil,
            recoveryConfidence: eligible ? .verified : .unknown
        )
    }
}
