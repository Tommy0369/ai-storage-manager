import Foundation

public enum ActionBindingFingerprintBuilder {
    public static func compute(input: MutationGateInput) -> ActionBindingFingerprint {
        let path = (input.snapshot?.evidence.canonicalPath.isEmpty == false
            ? input.snapshot!.evidence.canonicalPath
            : input.item.detected.entity.path)
        let canonical = (path as NSString).standardizingPath
        let txVersion = input.transactionContract?.version ?? "NONE"
        let digest = semanticDigest(input: input)
        return ActionBindingFingerprint(
            entityID: input.item.detected.entity.id,
            action: input.action,
            canonicalPath: canonical,
            evidenceGeneration: input.evidenceGeneration,
            verificationGeneration: input.verificationGeneration,
            runtimeGeneration: input.runtimeGeneration,
            ruleVersion: input.ruleVersion,
            transactionContractVersion: txVersion,
            semanticBindingDigest: digest
        )
    }

    public static func semanticDigest(input: MutationGateInput) -> String {
        guard input.action == .vendorNativeCleanup else { return "" }
        let v = input.item.verification ?? input.snapshot?.verification
        if ActionPolicy.isHuggingFaceSnapshotEntity(input.item) {
            let rev = ActionPolicy.huggingFaceRevision(from: input.item) ?? ""
            let repo = ActionPolicy.huggingFaceRepoID(from: input.item) ?? ""
            let remote = v?.remoteReacquisitionProof
            let remoteID = [
                remote?.remoteIdentity,
                remote?.remoteRevisionOrDigest,
                remote?.status.rawValue,
            ].compactMap { $0 }.joined(separator: "|")
            let unique = v?.uniqueBytesProven.map(String.init) ?? ""
            let shared = v?.sharedBytesProven.map(String.init) ?? ""
            let ref = v?.referenceGraphConfidence.rawValue ?? ""
            let binaryFP = v?.vendorProofNotes.first(where: { $0.hasPrefix("HF_BINARY_FP=") }) ?? ""
            let cliBound = v?.vendorProofNotes.first(where: { $0.hasPrefix("HF_CLI_RESOLVED=") }) ?? ""
            let dryFP = v?.vendorProofNotes.first(where: { $0.hasPrefix("HF_DRY_RUN_FP=") }) ?? ""
            let cacheRoot = v?.vendorProofNotes.first(where: { $0.hasPrefix("HF_CACHE_ROOT=") }) ?? ""
            let raw = [
                repo,
                rev,
                cacheRoot,
                remoteID,
                ref,
                unique,
                shared,
                binaryFP,
                cliBound,
                dryFP,
                HuggingFaceNativeCleanupExecutor.contractVersion,
            ].joined(separator: "#")
            return stableHash(raw)
        }
        let model = ActionPolicy.ollamaCanonicalModelName(from: input.item)
            ?? input.item.detected.entity.displayName
        let localManifest = v?.vendorProofNotes.first(where: { $0.hasPrefix("LOCAL_MANIFEST=") })
            ?? v?.reconstructionMechanism
            ?? ""
        let remote = v?.remoteReacquisitionProof
        // Exact remote identity only — freshness class lives in FreshnessEnvelope, not digest.
        let remoteID = [
            remote?.remoteIdentity,
            remote?.remoteRevisionOrDigest,
            remote?.status.rawValue,
        ].compactMap { $0 }.joined(separator: "|")
        let unique = v?.uniqueBytesProven.map(String.init) ?? ""
        let shared = v?.sharedBytesProven.map(String.init) ?? ""
        let ref = v?.referenceGraphConfidence.rawValue ?? ""
        let binaryFP = v?.vendorProofNotes.first(where: { $0.hasPrefix("OLLAMA_BINARY_FP=") }) ?? ""
        let cliBound = v?.vendorProofNotes.first(where: { $0.hasPrefix("OLLAMA_CLI_RESOLVED=") }) ?? ""
        // Intentionally excluded from digest: verifiedAt/freshUntil epochs, session IDs, latency.
        let raw = [
            model,
            localManifest,
            remoteID,
            ref,
            unique,
            shared,
            binaryFP,
            cliBound,
            OllamaNativeCleanupExecutor.contractVersion,
        ].joined(separator: "#")
        return stableHash(raw)
    }

    public static func stablePublicHash(_ raw: String) -> String {
        var hash: UInt64 = 5381
        for b in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(b)
        }
        return String(hash, radix: 16)
    }

    private static func stableHash(_ raw: String) -> String {
        stablePublicHash(raw)
    }

    public static func isApprovalValid(
        approval: UserActionApproval,
        fingerprint: ActionBindingFingerprint
    ) -> Bool {
        approval.bindingFingerprint.matches(fingerprint)
            && approval.entityID == fingerprint.entityID
            && approval.action == fingerprint.action
    }

    public static func invalidationReasons(
        approval: UserActionApproval,
        current: ActionBindingFingerprint,
        decision: ActionDecision
    ) -> [String] {
        var reasons: [String] = []
        if approval.entityID != current.entityID { reasons.append("ENTITY_ID_CHANGED") }
        if approval.action != current.action { reasons.append("ACTION_CHANGED") }
        if approval.bindingFingerprint.canonicalPath != current.canonicalPath { reasons.append("PATH_CHANGED") }
        if approval.bindingFingerprint.evidenceGeneration != current.evidenceGeneration {
            reasons.append("EVIDENCE_GENERATION_CHANGED")
        }
        if approval.bindingFingerprint.verificationGeneration != current.verificationGeneration {
            reasons.append("VERIFICATION_GENERATION_CHANGED")
        }
        if approval.bindingFingerprint.runtimeGeneration != current.runtimeGeneration {
            reasons.append("RUNTIME_GENERATION_STALE")
        }
        if approval.bindingFingerprint.transactionContractVersion != current.transactionContractVersion {
            reasons.append("TRANSACTION_CONTRACT_VERSION_CHANGED")
        }
        if approval.bindingFingerprint.semanticBindingDigest != current.semanticBindingDigest {
            reasons.append("SEMANTIC_BINDING_CHANGED")
        }
        if !decision.eligible { reasons.append("SAFETY_DECISION_CHANGED") }
        if decision.blockedReasons.contains(.evidenceConflict) { reasons.append("EVIDENCE_CONFLICT") }
        return reasons
    }

    public static func buildReceipt(input: MutationGateInput, fingerprint: ActionBindingFingerprint) -> PreflightReceipt {
        let pre = input.preflight
        return PreflightReceipt(
            receiptID: "preflight-\(input.item.detected.entity.id)-\(input.action.rawValue)",
            entityID: input.item.detected.entity.id,
            action: input.action,
            bindingFingerprint: fingerprint,
            requiredClaims: input.actionDecision.requiredClaims.map(\.claimType),
            satisfiedClaims: pre?.satisfied ?? input.actionDecision.satisfiedClaimTypes,
            missingClaims: pre?.missing ?? input.actionDecision.missingClaimTypes,
            staleClaims: pre?.stale ?? [],
            conflictedClaims: pre?.conflicted ?? [],
            observedAt: Date(),
            freshnessValidity: input.transactionContract?.freshnessRequirements ?? [],
            evidenceGeneration: input.evidenceGeneration,
            verificationGeneration: input.verificationGeneration,
            runtimeGeneration: input.runtimeGeneration,
            result: pre?.allowed == true ? "PREFLIGHT_OBSERVED" : "PREFLIGHT_INCOMPLETE"
        )
    }
}
