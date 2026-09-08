import Foundation

/// P2.1 trash + P3.2A Ollama MODEL + P3.2B HF SNAPSHOT vendor-native.
public enum ActionExecutionPolicy {
    public static let authorizedPhase = "P2.1+P3.2A+P3.2B"
    public static let authorizedActions: Set<StorageAction> = [.moveToTrash, .vendorNativeCleanup]

    public static func allowsFirstMutationTrash(entityID: String, path: String) -> Bool {
        guard !isBroadAggregateRoot(entityID: entityID, path: path) else { return false }
        let lowerPath = path.lowercased()
        let lowerID = entityID.lowercased()
        guard lowerPath.contains("/deriveddata/"), lowerID.contains("deriveddata") else { return false }
        guard !HardSafetyGates.isHardBlocked(path: path) else { return false }
        return true
    }

    public static func allowsOllamaNativeCleanup(entityID: String, path: String, canonicalModel: String) -> Bool {
        guard ActionPolicy.isOllamaModelEntity(entityID: entityID, path: path) else { return false }
        guard !ActionPolicy.isRawAIVendorBlob(entityID: entityID, path: path) else { return false }
        guard OllamaModelIdentity.isValidCanonical(canonicalModel) else { return false }
        guard !isBroadAggregateRoot(entityID: entityID, path: path) else { return false }
        guard !HardSafetyGates.isHardBlocked(path: path) else { return false }
        return true
    }

    public static func allowsHuggingFaceNativeCleanup(
        entityID: String,
        path: String,
        revision: String,
        cacheRoot: String
    ) -> Bool {
        guard ActionPolicy.isHuggingFaceSnapshotEntity(entityID: entityID, path: path) else { return false }
        guard !ActionPolicy.isRawAIVendorBlob(entityID: entityID, path: path) else { return false }
        guard HuggingFaceRevisionIdentity.isValidFullRevision(revision) else { return false }
        guard !revision.contains("/"), !revision.lowercased().hasPrefix("model/") else { return false }
        let root = (cacheRoot as NSString).standardizingPath
        guard root.lowercased().contains("/huggingface/hub") else { return false }
        guard path.lowercased().hasPrefix(root.lowercased())
            || path.lowercased().contains("/huggingface/hub/") else { return false }
        guard !isBroadAggregateRoot(entityID: entityID, path: path) else { return false }
        guard !HardSafetyGates.isHardBlocked(path: path) else { return false }
        return true
    }

    public static func isBroadAggregateRoot(entityID: String, path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let broadPaths = [
            "Downloads", "Documents", "Desktop",
            "Library/Application Support", "Library/Caches", "Library/Containers",
            "Library/Developer/Xcode/DerivedData",
        ].map { (home as NSString).appendingPathComponent($0) }
        if broadPaths.contains(normalized) { return true }
        let broadIDs: Set<String> = [
            "user.downloads", "user.documents", "user.desktop",
            "xcode.derived_data", "macos.application_support",
        ]
        if broadIDs.contains(entityID) { return true }
        if entityID.hasSuffix(".root") { return true }
        return false
    }

    public static func validatePermit(_ permit: ExecutionPermit, plan: DryRunActionPlan) throws {
        guard permit.action == .moveToTrash else {
            throw ActionExecutionError.unauthorizedAction(permit.action)
        }
        guard plan.action == StorageAction.moveToTrash.rawValue else {
            throw ActionExecutionError.planActionMismatch(plan.action)
        }
        guard permit.entityID == plan.entityID else {
            throw ActionExecutionError.entityMismatch(expected: permit.entityID, actual: plan.entityID)
        }
        let path = (plan.path as NSString).standardizingPath
        guard path == permit.bindingFingerprint.canonicalPath else {
            throw ActionExecutionError.bindingPathMismatch
        }
        guard allowsFirstMutationTrash(entityID: permit.entityID, path: path) else {
            throw ActionExecutionError.unauthorizedTarget(entityID: permit.entityID, path: path)
        }
    }

    public static func validateOllamaNativePermit(
        _ permit: ExecutionPermit,
        plan: DryRunActionPlan,
        canonicalModel: String
    ) throws {
        guard permit.action == .vendorNativeCleanup else {
            throw ActionExecutionError.unauthorizedAction(permit.action)
        }
        guard plan.action == StorageAction.vendorNativeCleanup.rawValue else {
            throw ActionExecutionError.planActionMismatch(plan.action)
        }
        guard permit.entityID == plan.entityID else {
            throw ActionExecutionError.entityMismatch(expected: permit.entityID, actual: plan.entityID)
        }
        let path = (plan.path as NSString).standardizingPath
        guard path == permit.bindingFingerprint.canonicalPath else {
            throw ActionExecutionError.bindingPathMismatch
        }
        guard allowsOllamaNativeCleanup(
            entityID: permit.entityID,
            path: path,
            canonicalModel: canonicalModel
        ) else {
            throw ActionExecutionError.unauthorizedTarget(entityID: permit.entityID, path: path)
        }
        if ExecutionPermitLedger.isConsumed(permit.permitID) {
            throw ActionExecutionError.permitAlreadyConsumed(permit.permitID)
        }
    }

    public static func validateHuggingFaceNativePermit(
        _ permit: ExecutionPermit,
        plan: DryRunActionPlan,
        revision: String,
        cacheRoot: String
    ) throws {
        guard permit.action == .vendorNativeCleanup else {
            throw ActionExecutionError.unauthorizedAction(permit.action)
        }
        guard plan.action == StorageAction.vendorNativeCleanup.rawValue else {
            throw ActionExecutionError.planActionMismatch(plan.action)
        }
        guard permit.entityID == plan.entityID else {
            throw ActionExecutionError.entityMismatch(expected: permit.entityID, actual: plan.entityID)
        }
        let path = (plan.path as NSString).standardizingPath
        guard path == permit.bindingFingerprint.canonicalPath else {
            throw ActionExecutionError.bindingPathMismatch
        }
        guard allowsHuggingFaceNativeCleanup(
            entityID: permit.entityID,
            path: path,
            revision: revision,
            cacheRoot: cacheRoot
        ) else {
            throw ActionExecutionError.unauthorizedTarget(entityID: permit.entityID, path: path)
        }
        if ExecutionPermitLedger.isConsumed(permit.permitID) {
            throw ActionExecutionError.permitAlreadyConsumed(permit.permitID)
        }
    }
}

public enum ActionExecutionError: Error, Equatable, Sendable {
    case unauthorizedAction(StorageAction)
    case unauthorizedTarget(entityID: String, path: String)
    case planActionMismatch(String)
    case entityMismatch(expected: String, actual: String)
    case bindingPathMismatch
    case sourceMissing(String)
    case trashFailed(String)
    case postVerifyFailed(String)
    case executorNotImplemented(StorageAction)
    case permitDenied(String)
    case preflightNotReady(String)
    case humanConfirmationRequired
    case gateNotReady(String)
    case invalidModelIdentity(String)
    case executableUnresolved(String)
    case permitAlreadyConsumed(String)
    case processFailed(String)
}

public struct ActFirstMutationExecutionReport: Codable, Sendable, Equatable {
    public var phase: String
    public var outcome: String
    public var entityID: String
    public var action: String
    public var path: String
    public var preflightSessionID: String?
    public var approvalID: String?
    public var permitID: String?
    public var auditRecord: ActionAuditRecord?
    public var postVerifySteps: [PostActionVerifyStepResult]
    public var measuredRecoveryBytes: Int64?
    public var trashDestinationPath: String?
    public var executionMs: Int
    public var humanConfirmed: Bool
    public var executorImplemented: Bool
    public var destructiveActionsExecuted: Bool
    public var explanation: String
    public var postMutationVerification: PostMutationVerificationResult?

    public init(
        phase: String,
        outcome: String,
        entityID: String,
        action: String,
        path: String,
        preflightSessionID: String? = nil,
        approvalID: String? = nil,
        permitID: String? = nil,
        auditRecord: ActionAuditRecord? = nil,
        postVerifySteps: [PostActionVerifyStepResult] = [],
        measuredRecoveryBytes: Int64? = nil,
        trashDestinationPath: String? = nil,
        executionMs: Int = 0,
        humanConfirmed: Bool,
        executorImplemented: Bool,
        destructiveActionsExecuted: Bool,
        explanation: String,
        postMutationVerification: PostMutationVerificationResult? = nil
    ) {
        self.phase = phase
        self.outcome = outcome
        self.entityID = entityID
        self.action = action
        self.path = path
        self.preflightSessionID = preflightSessionID
        self.approvalID = approvalID
        self.permitID = permitID
        self.auditRecord = auditRecord
        self.postVerifySteps = postVerifySteps
        self.measuredRecoveryBytes = measuredRecoveryBytes
        self.trashDestinationPath = trashDestinationPath
        self.executionMs = executionMs
        self.humanConfirmed = humanConfirmed
        self.executorImplemented = executorImplemented
        self.destructiveActionsExecuted = destructiveActionsExecuted
        self.explanation = explanation
        self.postMutationVerification = postMutationVerification
    }
}

public struct PostActionVerifyStepResult: Codable, Sendable, Equatable {
    public var step: String
    public var satisfied: Bool
    public var detail: String?
}
