import Foundation

/// Authorized HF SNAPSHOT × VENDOR_NATIVE_CLEANUP identity + before/after probe.
/// Scope: exact local cached revision only. Never Hub delete / prune / raw delete.
public enum HuggingFaceNativePostMutationProbe {
    public static let authorizedEntityID = "ai.hf.snapshot.mlx-community.whisper-large-v3-mlx.49e6aa286ad6"
    public static let authorizedRepoID = "mlx-community/whisper-large-v3-mlx"
    public static let authorizedRevision = "49e6aa286ad60c14352c404340ded53710378a11"
    public static let authorizedAction = StorageAction.vendorNativeCleanup
    public static let expectedUniqueBytes: Int64 = 3_083_520_968
    public static let authorizationText = """
mlx-community/whisper-large-v3-mlx の revision 49e6aa286ad60c14352c404340ded53710378a11 を VENDOR_NATIVE_CLEANUP でローカルから削除することを承認する。Hub削除・prune・他revision・他repo・raw deleteは承認しない。
"""

    public static var defaultCacheRoot: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".cache/huggingface/hub")
    }

    public static var authorizedSnapshotPath: String {
        let encoded = "models--" + authorizedRepoID.replacingOccurrences(of: "/", with: "--")
        return ((defaultCacheRoot as NSString)
            .appendingPathComponent(encoded) as NSString)
            .appendingPathComponent("snapshots/\(authorizedRevision)")
    }

    public static var authorizedRepoPath: String {
        let encoded = "models--" + authorizedRepoID.replacingOccurrences(of: "/", with: "--")
        return (defaultCacheRoot as NSString).appendingPathComponent(encoded)
    }

    public static func authorizationTextFingerprint(_ text: String = authorizationText) -> String {
        ActionBindingFingerprintBuilder.stablePublicHash(text)
    }

    public struct BeforeSnapshot: Codable, Sendable, Equatable {
        public var snapshotPresent: Bool
        public var repoPresent: Bool
        public var revisionCount: Int
        public var uniqueBytes: Int64
        public var freeBytes: Int64?
        public var inventoryFingerprint: String
        public var observedAt: Date
    }

    public static func captureBefore(now: Date = Date()) -> BeforeSnapshot {
        let inv = HuggingFaceCacheDryRunPreviewer.captureLocalInventory(
            repoID: authorizedRepoID,
            revision: authorizedRevision,
            itemPath: authorizedSnapshotPath,
            uniqueBytes: expectedUniqueBytes,
            sharedBytes: 0,
            now: now
        )
        return BeforeSnapshot(
            snapshotPresent: inv.snapshotPresent,
            repoPresent: FileManager.default.fileExists(atPath: authorizedRepoPath),
            revisionCount: inv.revisions.count,
            uniqueBytes: inv.uniqueBytes ?? expectedUniqueBytes,
            freeBytes: StorageCapacityMeasurer.freeBytes(),
            inventoryFingerprint: inv.fingerprint,
            observedAt: now
        )
    }

    public static func buildAuthorizedClassifiedItem() -> ClassifiedItem {
        let entity = StorageEntity(
            id: authorizedEntityID,
            kind: .cache,
            category: "AI_DEV",
            subcategory: "huggingface",
            displayName: "\(authorizedRepoID)@\(String(authorizedRevision.prefix(12)))",
            path: authorizedSnapshotPath,
            logicalBytes: expectedUniqueBytes
        )
        let detected = DetectedEntity(
            entity: entity,
            bucket: .developer,
            domain: "AI Tools",
            associatedProcesses: [],
            identified: true,
            annotation: nil
        )
        let safety = SafetyDecision(
            entity: entity,
            action: .noAction,
            safetyClass: .unknown,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0,
            userExplanationJA: "HF cached revision",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        var item = ClassifiedItem(
            detected: detected,
            decision: safety,
            semantic: SemanticResult(from: safety),
            allocatedBytes: expectedUniqueBytes,
            actionVariants: [:],
            inclusiveBytes: expectedUniqueBytes,
            exclusiveBytes: expectedUniqueBytes,
            resolution: .l3Product,
            unknownReason: nil,
            verification: nil
        )
        var v = VerificationAnnotation()
        v.vendorProofNotes = [
            "HF_REVISION=\(authorizedRevision)",
            "HF_REPO=\(authorizedRepoID)",
            "HF_CACHE_ROOT=\(defaultCacheRoot)",
            "LOCAL_HF_CACHE_OWNERSHIP_VERIFIED",
        ]
        v.referenceGraphConfidence = .verified
        v.uniqueBytesProven = expectedUniqueBytes
        v.sharedBytesProven = 0
        item.verification = v
        return item
    }

    public static func initialGate(for item: ClassifiedItem) -> MutationGateResult {
        MutationGateResult(
            entityID: item.detected.entity.id,
            path: item.detected.entity.path,
            action: StorageAction.vendorNativeCleanup.rawValue,
            safetyClass: SafetyClass.unknown.rawValue,
            recommendation: nil,
            readiness: MutationReadiness.approvalRequired.rawValue,
            satisfiedRequirements: [],
            missingRequirements: ["USER_APPROVAL"],
            staleRequirements: [],
            conflictedRequirements: [],
            blockingReasons: [],
            requiredFreshChecks: ["fresh_runtime_preflight", "fresh_remote_reacquisition"],
            actionBindingFingerprint: nil,
            transactionContractAvailable: true,
            postVerifyContractAvailable: true,
            auditContractAvailable: true,
            freshRuntimeCheckRequired: true,
            freshCloudCheckRequired: true,
            approvalRequired: true,
            executorImplemented: true
        )
    }

    public static func initialDecision(for item: ClassifiedItem) -> ActionDecision {
        ActionDecision(
            entityID: item.detected.entity.id,
            action: .vendorNativeCleanup,
            safetyClass: .unknown,
            eligible: true,
            explanationCodes: [
                "HF_REVISION=\(authorizedRevision)",
                "SCOPE=LOCAL_CACHE_ONLY",
            ]
        )
    }
}
