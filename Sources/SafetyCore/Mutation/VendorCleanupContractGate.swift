import Foundation

/// P3.3C.1 — permanent product invariant:
/// A cleanup *command* is only a capability signal.
/// It becomes an actionable cleanup *contract* only when
/// Vendor × Store × ExactTarget × BlastRadius × State align.
///
/// Capability ≠ Permission. Cleanup Command ≠ Cleanup Contract.
/// This gate does NOT assign SafetyClass / does NOT create GREEN.

public enum VendorCleanupAlignmentStatus: String, Codable, Sendable, Equatable {
    case aligned = "ALIGNED"
    case storeMismatch = "STORE_MISMATCH"
    case targetMismatch = "TARGET_MISMATCH"
    case blastRadiusUnbounded = "BLAST_RADIUS_UNBOUNDED"
    case contractUnreachable = "CONTRACT_UNREACHABLE"
    case semanticClassMismatch = "SEMANTIC_CLASS_MISMATCH"
    case verifyMore = "VERIFY_MORE"
    case blocked = "BLOCKED"
}

public enum VendorCleanupTargetSelectorKind: String, Codable, Sendable, Equatable {
    case exactVersion = "EXACT_VERSION"
    case exactRevision = "EXACT_REVISION"
    case exactModel = "EXACT_MODEL"
    case vendorStaleSet = "VENDOR_STALE_SET"
    case atomicVendorSet = "ATOMIC_VENDOR_SET"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

public enum VendorCleanupFutureActionUnit: String, Codable, Sendable, Equatable {
    case exactVersion = "EXACT_VERSION"
    case vendorStaleSet = "VENDOR_STALE_SET"
    case atomicVendorSet = "ATOMIC_VENDOR_SET"
    case none = "NONE"
    case unknown = "UNKNOWN"
}

/// Expanded cleanup contract used by the gate (supersedes thin P3.3C stub usage).
public struct VendorCleanupContractSpec: Codable, Sendable, Equatable {
    public var vendor: String
    public var storageClass: String
    public var actionClass: String

    public var declaredTargetRoot: String
    public var resolvedTargetRoot: String

    public var targetSelectorKind: VendorCleanupTargetSelectorKind
    public var targetSelector: String

    public var currentTargetExclusions: [String]
    public var fallbackExclusions: [String]

    public var blastRadius: String
    public var blastRadiusBound: Bool

    public var previewCapability: Bool
    public var dryRunCapability: Bool

    public var runtimeRequirements: String
    public var reacquisitionRequirements: String

    public var postVerifyContract: String
    public var auditContract: String

    public var sourceEvidence: String
    public var confidence: String
    public var contractReachable: Bool

    public init(
        vendor: String,
        storageClass: String,
        actionClass: String,
        declaredTargetRoot: String,
        resolvedTargetRoot: String,
        targetSelectorKind: VendorCleanupTargetSelectorKind,
        targetSelector: String,
        currentTargetExclusions: [String],
        fallbackExclusions: [String],
        blastRadius: String,
        blastRadiusBound: Bool,
        previewCapability: Bool,
        dryRunCapability: Bool,
        runtimeRequirements: String,
        reacquisitionRequirements: String,
        postVerifyContract: String,
        auditContract: String,
        sourceEvidence: String,
        confidence: String,
        contractReachable: Bool
    ) {
        self.vendor = vendor
        self.storageClass = storageClass
        self.actionClass = actionClass
        self.declaredTargetRoot = declaredTargetRoot
        self.resolvedTargetRoot = resolvedTargetRoot
        self.targetSelectorKind = targetSelectorKind
        self.targetSelector = targetSelector
        self.currentTargetExclusions = currentTargetExclusions
        self.fallbackExclusions = fallbackExclusions
        self.blastRadius = blastRadius
        self.blastRadiusBound = blastRadiusBound
        self.previewCapability = previewCapability
        self.dryRunCapability = dryRunCapability
        self.runtimeRequirements = runtimeRequirements
        self.reacquisitionRequirements = reacquisitionRequirements
        self.postVerifyContract = postVerifyContract
        self.auditContract = auditContract
        self.sourceEvidence = sourceEvidence
        self.confidence = confidence
        self.contractReachable = contractReachable
    }
}

public struct VendorCleanupEntityContext: Codable, Sendable, Equatable {
    public var vendor: String
    public var storageClass: String
    public var entityID: String
    public var exactTargetID: String
    public var storeCanonicalPath: String
    public var isCurrent: Bool
    public var isActive: Bool
    public var isFallbackProtected: Bool
    public var requiredProofsUnknown: [String]
    public var requiredProofsConflict: [String]

    public init(
        vendor: String,
        storageClass: String,
        entityID: String,
        exactTargetID: String,
        storeCanonicalPath: String,
        isCurrent: Bool = false,
        isActive: Bool = false,
        isFallbackProtected: Bool = false,
        requiredProofsUnknown: [String] = [],
        requiredProofsConflict: [String] = []
    ) {
        self.vendor = vendor
        self.storageClass = storageClass
        self.entityID = entityID
        self.exactTargetID = exactTargetID
        self.storeCanonicalPath = storeCanonicalPath
        self.isCurrent = isCurrent
        self.isActive = isActive
        self.isFallbackProtected = isFallbackProtected
        self.requiredProofsUnknown = requiredProofsUnknown
        self.requiredProofsConflict = requiredProofsConflict
    }
}

public struct VendorCleanupAlignmentResult: Codable, Sendable, Equatable {
    public var vendorMatches: Bool
    public var storageClassMatches: Bool
    public var storePathRelationship: CleanupTargetRelationship
    public var exactTargetMatches: Bool
    public var selectorMatches: Bool
    public var blastRadiusBound: Bool
    public var currentStateCompatible: Bool
    public var contractReachable: Bool
    public var strictUnknowns: [String]
    public var strictConflicts: [String]
    public var alignmentStatus: VendorCleanupAlignmentStatus
    public var mayReachApprovalBoundary: Bool
    public var assignsSafetyClass: Bool

    public static let assignsSafetyClassAlwaysFalse = false
}

public enum VendorCleanupContractInvariant {
    /// Testable permanent product rule.
    public static let noVendorCleanupWithoutAlignedContract =
        "NO_VENDOR_CLEANUP_ACTION_WITHOUT_ALIGNED_CONTRACT"

    public static let capabilityIsPermission = false
    public static let cleanupCommandIsContract = false
    public static let approvalCannotOverrideUnknown = true
    public static let approvalCannotOverrideMismatch = true

    public static let requiredDimensions: [String] = [
        "vendor", "store", "exactTarget", "blastRadius", "state",
    ]

    public static func actionabilityAllowed(alignment: VendorCleanupAlignmentResult) -> Bool {
        alignment.alignmentStatus == .aligned && alignment.mayReachApprovalBoundary
    }
}

/// Gate placement (conceptual):
/// ActionRecommendation → ActionSafetyEvaluator → ActionDecision
/// → **VendorCleanupContractGate** → Fresh Preflight → Approval → Permit → Executor
public enum VendorCleanupContractGate {
    public static func evaluate(
        entity: VendorCleanupEntityContext,
        contract: VendorCleanupContractSpec?,
        actionIsVendorNativeCleanup: Bool
    ) -> VendorCleanupAlignmentResult {
        guard actionIsVendorNativeCleanup else {
            return blocked(
                vendorMatches: false,
                storageClassMatches: false,
                relationship: .unknown,
                exactTarget: false,
                selector: false,
                blastBound: false,
                stateOK: false,
                reachable: false,
                unknowns: ["action_not_vendor_native_cleanup"],
                conflicts: [],
                status: .blocked
            )
        }

        guard let contract else {
            return blocked(
                vendorMatches: false,
                storageClassMatches: false,
                relationship: .unknown,
                exactTarget: false,
                selector: false,
                blastBound: false,
                stateOK: false,
                reachable: false,
                unknowns: ["cleanup_contract_absent"],
                conflicts: [],
                status: .verifyMore
            )
        }

        var unknowns: [String] = entity.requiredProofsUnknown
        var conflicts: [String] = entity.requiredProofsConflict

        let vendorMatches = contract.vendor == entity.vendor
        let storageClassMatches = contract.storageClass == entity.storageClass

        let relationship = CursorAgentCLIPathAlignment.relationship(
            actualCanonical: entity.storeCanonicalPath,
            cleanupCanonical: contract.resolvedTargetRoot
        )

        if !contract.contractReachable {
            return blocked(
                vendorMatches: vendorMatches,
                storageClassMatches: storageClassMatches,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: contract.blastRadiusBound,
                stateOK: false,
                reachable: false,
                unknowns: unknowns + ["contract_unreachable"],
                conflicts: conflicts,
                status: .contractUnreachable
            )
        }

        if !vendorMatches {
            return blocked(
                vendorMatches: false,
                storageClassMatches: storageClassMatches,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: contract.blastRadiusBound,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts + ["vendor_mismatch"],
                status: .blocked
            )
        }

        if !storageClassMatches {
            return blocked(
                vendorMatches: true,
                storageClassMatches: false,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: contract.blastRadiusBound,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts + ["storage_class_mismatch"],
                status: .semanticClassMismatch
            )
        }

        // Store path must EXACT_ROOT_MATCH for installed-version style contracts.
        let storeAligned = relationship == .exactRootMatch
        if !storeAligned {
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: contract.blastRadiusBound,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts + ["store_path_mismatch:\(relationship.rawValue)"],
                status: .storeMismatch
            )
        }

        if !contract.blastRadiusBound {
            unknowns.append("blast_radius_unbounded")
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: false,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts,
                status: .blastRadiusUnbounded
            )
        }

        // Exact target / selector
        let selectorKind = contract.targetSelectorKind
        if selectorKind == .unknown {
            unknowns.append("selector_unknown")
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: true,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts,
                status: .verifyMore
            )
        }

        let exactTargetMatches: Bool
        let selectorMatches: Bool
        switch selectorKind {
        case .exactVersion, .exactRevision, .exactModel:
            // Contract selector string must mention exact target id (or equal).
            exactTargetMatches =
                contract.targetSelector == entity.exactTargetID
                || contract.targetSelector.contains(entity.exactTargetID)
            selectorMatches = exactTargetMatches
            if !exactTargetMatches {
                return blocked(
                    vendorMatches: true,
                    storageClassMatches: true,
                    relationship: relationship,
                    exactTarget: false,
                    selector: false,
                    blastBound: true,
                    stateOK: false,
                    reachable: true,
                    unknowns: unknowns,
                    conflicts: conflicts + ["target_mismatch"],
                    status: .targetMismatch
                )
            }
        case .vendorStaleSet, .atomicVendorSet:
            // Set-based: entity must be eligible under selector text; exact id match not required.
            exactTargetMatches = true
            selectorMatches = true
        case .none:
            exactTargetMatches = false
            selectorMatches = false
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: false,
                selector: false,
                blastBound: true,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts + ["selector_none"],
                status: .blocked
            )
        case .unknown:
            exactTargetMatches = false
            selectorMatches = false
        }

        // Current / active / fallback protection
        if entity.isActive {
            conflicts.append("active_version_included")
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: exactTargetMatches,
                selector: selectorMatches,
                blastBound: true,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts,
                status: .blocked
            )
        }
        if entity.isCurrent {
            conflicts.append("current_version_included")
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: exactTargetMatches,
                selector: selectorMatches,
                blastBound: true,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts,
                status: .blocked
            )
        }
        if entity.isFallbackProtected {
            conflicts.append("fallback_version_included")
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: exactTargetMatches,
                selector: selectorMatches,
                blastBound: true,
                stateOK: false,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts,
                status: .blocked
            )
        }

        if !unknowns.isEmpty {
            return blocked(
                vendorMatches: true,
                storageClassMatches: true,
                relationship: relationship,
                exactTarget: exactTargetMatches,
                selector: selectorMatches,
                blastBound: true,
                stateOK: true,
                reachable: true,
                unknowns: unknowns,
                conflicts: conflicts,
                status: .verifyMore
            )
        }

        // ALIGNED — may reach approval boundary later; never assigns SafetyClass; not executable here.
        return VendorCleanupAlignmentResult(
            vendorMatches: true,
            storageClassMatches: true,
            storePathRelationship: relationship,
            exactTargetMatches: exactTargetMatches,
            selectorMatches: selectorMatches,
            blastRadiusBound: true,
            currentStateCompatible: true,
            contractReachable: true,
            strictUnknowns: [],
            strictConflicts: [],
            alignmentStatus: .aligned,
            mayReachApprovalBoundary: true,
            assignsSafetyClass: false
        )
    }

    private static func blocked(
        vendorMatches: Bool,
        storageClassMatches: Bool,
        relationship: CleanupTargetRelationship,
        exactTarget: Bool,
        selector: Bool,
        blastBound: Bool,
        stateOK: Bool,
        reachable: Bool,
        unknowns: [String],
        conflicts: [String],
        status: VendorCleanupAlignmentStatus
    ) -> VendorCleanupAlignmentResult {
        VendorCleanupAlignmentResult(
            vendorMatches: vendorMatches,
            storageClassMatches: storageClassMatches,
            storePathRelationship: relationship,
            exactTargetMatches: exactTarget,
            selectorMatches: selector,
            blastRadiusBound: blastBound,
            currentStateCompatible: stateOK,
            contractReachable: reachable,
            strictUnknowns: unknowns,
            strictConflicts: conflicts,
            alignmentStatus: status,
            mayReachApprovalBoundary: false,
            assignsSafetyClass: false
        )
    }

    // MARK: - Fixture contracts for cross-vendor regression (not live execution)

    public static let ollamaModelFixtureContract = VendorCleanupContractSpec(
        vendor: "OLLAMA",
        storageClass: "MANAGED_MODEL_STORE",
        actionClass: "VENDOR_NATIVE_CLEANUP",
        declaredTargetRoot: "~/.ollama/models",
        resolvedTargetRoot: "~/.ollama/models",
        targetSelectorKind: .exactModel,
        targetSelector: "library/qwen3:4b",
        currentTargetExclusions: [],
        fallbackExclusions: [],
        blastRadius: "exact native model cleanup via ollama rm",
        blastRadiusBound: true,
        previewCapability: false,
        dryRunCapability: false,
        runtimeRequirements: "ollama CLI present; model inactive",
        reacquisitionRequirements: "remote manifest VERIFIED",
        postVerifyContract: "POST_MUTATION_PROBE",
        auditContract: "VerifiedActionResult",
        sourceEvidence: "P3.2A.5 real path",
        confidence: "VERIFIED",
        contractReachable: true
    )

    public static let huggingFaceRevisionFixtureContract = VendorCleanupContractSpec(
        vendor: "HUGGING_FACE",
        storageClass: "HF_HUB_CACHE",
        actionClass: "VENDOR_NATIVE_CLEANUP",
        declaredTargetRoot: "~/.cache/huggingface/hub",
        resolvedTargetRoot: "~/.cache/huggingface/hub",
        targetSelectorKind: .exactRevision,
        targetSelector: "49e6aa286ad6",
        currentTargetExclusions: [],
        fallbackExclusions: [],
        blastRadius: "vendor dry-run proven last-revision → repo dir disappearance (semantic exact)",
        blastRadiusBound: true,
        previewCapability: true,
        dryRunCapability: true,
        runtimeRequirements: "hf CLI; Fresh Preflight",
        reacquisitionRequirements: "Hub revision HTTP proof",
        postVerifyContract: "POST_MUTATION_PROBE",
        auditContract: "VerifiedActionResult + CLI consent",
        sourceEvidence: "P3.2B.3 real path",
        confidence: "VERIFIED",
        contractReachable: true
    )

    /// Cursor HOME cleanup contract — LIVE but does not cover GS worker store.
    public static func cursorHomeInstallCleanupContract(resolvedHomeVersions: String) -> VendorCleanupContractSpec {
        VendorCleanupContractSpec(
            vendor: "CURSOR",
            storageClass: "INSTALLED_VERSIONS",
            actionClass: "VENDOR_NATIVE_CLEANUP",
            declaredTargetRoot: "join(homedir(), \".local\", \"share\", \"cursor-agent\", \"versions\")",
            resolvedTargetRoot: resolvedHomeVersions,
            targetSelectorKind: .vendorStaleSet,
            targetSelector: "non-current keep-2-newest; skip in-use",
            currentTargetExclusions: ["currentVersion"],
            fallbackExclusions: ["2 newest non-current"],
            blastRadius: "HOME versions dirs only",
            blastRadiusBound: true,
            previewCapability: false,
            dryRunCapability: false,
            runtimeRequirements: "agent CLI binary",
            reacquisitionRequirements: "UNKNOWN for historical builds",
            postVerifyContract: "UNKNOWN",
            auditContract: "UNKNOWN",
            sourceEvidence: "install-core-posix cleanup-install-versions",
            confidence: "VERIFIED_FOR_HOME_STORE",
            contractReachable: true
        )
    }
}
