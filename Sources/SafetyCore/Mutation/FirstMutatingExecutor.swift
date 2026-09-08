import Foundation

/// P2.1 — First authorized mutating executor. MOVE_TO_TRASH (DerivedData child) only.
public struct FirstMutatingExecutor: StorageActionExecutor {
    public var trashItem: (_ source: URL) throws -> URL

    public init(
        trashItem: @escaping (_ source: URL) throws -> URL = FirstMutatingExecutor.defaultTrashItem
    ) {
        self.trashItem = trashItem
    }

    public static let shared = FirstMutatingExecutor()
    public static var isAvailable: Bool { true }
    public var isImplemented: Bool { true }

    public func executeTrash(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord {
        try ActionExecutionPolicy.validatePermit(permit, plan: plan)
        let sourcePath = (plan.path as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw ActionExecutionError.sourceMissing(sourcePath)
        }
        let started = Date()
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let trashURL: URL
        do {
            trashURL = try trashItem(sourceURL)
        } catch {
            throw ActionExecutionError.trashFailed(error.localizedDescription)
        }
        return ActionAuditRecord(
            actionID: permit.permitID,
            entityID: plan.entityID,
            action: .moveToTrash,
            sourcePath: sourcePath,
            destinationPath: trashURL.path,
            preflightClaims: [],
            transactionPhase: TrashTransactionPhase.movingToTrash.rawValue,
            logicalBytesAffected: nil,
            measuredRecoveryBytes: nil,
            failureReason: nil,
            startedAt: started
        )
    }

    public func executeICloudMove(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord {
        _ = plan
        _ = permit
        throw ActionExecutionError.executorNotImplemented(.moveToICloud)
    }

    public func executeRemoveLocalDownload(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord {
        _ = plan
        _ = permit
        throw ActionExecutionError.executorNotImplemented(.removeLocalDownload)
    }

    public static func defaultTrashItem(at source: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &resulting)
        guard let url = resulting as URL? else {
            throw ActionExecutionError.trashFailed("Trash API returned no destination URL")
        }
        return url
    }
}

public enum TrashPostActionVerifier {
    public static func verify(
        sourcePath: String,
        trashDestination: String?,
        contract: PostActionVerificationContract?
    ) -> (steps: [PostActionVerifyStepResult], measuredRecoveryBytes: Int64?) {
        let canonical = (sourcePath as NSString).standardizingPath
        var steps: [PostActionVerifyStepResult] = []
        let sourceGone = !FileManager.default.fileExists(atPath: canonical)
        steps.append(PostActionVerifyStepResult(
            step: "verify_source_no_longer_owns",
            satisfied: sourceGone,
            detail: sourceGone ? "absent" : "still_present"
        ))
        steps.append(PostActionVerifyStepResult(
            step: "verify_trash_operation_result",
            satisfied: sourceGone && trashDestination != nil,
            detail: trashDestination
        ))
        let measured = sourceGone ? measuredBytes(at: trashDestination) : nil
        steps.append(PostActionVerifyStepResult(
            step: "record_actual_recovered_bytes",
            satisfied: sourceGone,
            detail: measured.map(String.init)
        ))
        if let contract {
            for step in contract.verificationSteps where !steps.contains(where: { $0.step == step }) {
                steps.append(PostActionVerifyStepResult(step: step, satisfied: sourceGone, detail: nil))
            }
        }
        steps.append(PostActionVerifyStepResult(step: "complete_audit", satisfied: sourceGone, detail: nil))
        return (steps, measured)
    }

    private static func measuredBytes(at path: String?) -> Int64? {
        guard let path else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }
}
