import Foundation

/// Future mutation capability boundary. P2.1 trash + P3.2A Ollama + P3.2B HF native.
public protocol StorageActionExecutor: Sendable {
    var isImplemented: Bool { get }

    func executeTrash(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord
    func executeICloudMove(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord
    func executeRemoveLocalDownload(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord
    func executeVendorNativeCleanup(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        canonicalModel: String
    ) throws -> ActionAuditRecord
    func executeHuggingFaceRevisionCleanup(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        revision: String,
        cacheRoot: String
    ) throws -> ActionAuditRecord
}

public enum ActionExecutionBoundary {
    public static var executorImplemented: Bool { FirstMutatingExecutor.isAvailable }
}

extension FirstMutatingExecutor {
    public func executeVendorNativeCleanup(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        canonicalModel: String
    ) throws -> ActionAuditRecord {
        _ = plan
        _ = permit
        _ = canonicalModel
        throw ActionExecutionError.executorNotImplemented(.vendorNativeCleanup)
    }

    public func executeHuggingFaceRevisionCleanup(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        revision: String,
        cacheRoot: String
    ) throws -> ActionAuditRecord {
        _ = plan
        _ = permit
        _ = revision
        _ = cacheRoot
        throw ActionExecutionError.executorNotImplemented(.vendorNativeCleanup)
    }
}

/// Routes trash vs Ollama native vs HF revision native. No raw-delete fallback.
public struct StorageActionExecutorRouter: StorageActionExecutor {
    public var trashExecutor: FirstMutatingExecutor
    public var ollamaExecutor: OllamaNativeCleanupExecutor
    public var huggingFaceExecutor: HuggingFaceNativeCleanupExecutor

    public init(
        trashExecutor: FirstMutatingExecutor = .shared,
        ollamaExecutor: OllamaNativeCleanupExecutor = OllamaNativeCleanupExecutor(),
        huggingFaceExecutor: HuggingFaceNativeCleanupExecutor = HuggingFaceNativeCleanupExecutor()
    ) {
        self.trashExecutor = trashExecutor
        self.ollamaExecutor = ollamaExecutor
        self.huggingFaceExecutor = huggingFaceExecutor
    }

    public var isImplemented: Bool { true }

    public func executeTrash(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord {
        try trashExecutor.executeTrash(plan: plan, permit: permit)
    }

    public func executeICloudMove(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord {
        try trashExecutor.executeICloudMove(plan: plan, permit: permit)
    }

    public func executeRemoveLocalDownload(plan: DryRunActionPlan, permit: ExecutionPermit) throws -> ActionAuditRecord {
        try trashExecutor.executeRemoveLocalDownload(plan: plan, permit: permit)
    }

    public func executeVendorNativeCleanup(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        canonicalModel: String
    ) throws -> ActionAuditRecord {
        try ollamaExecutor.execute(plan: plan, permit: permit, canonicalModel: canonicalModel)
    }

    public func executeHuggingFaceRevisionCleanup(
        plan: DryRunActionPlan,
        permit: ExecutionPermit,
        revision: String,
        cacheRoot: String
    ) throws -> ActionAuditRecord {
        try huggingFaceExecutor.execute(
            plan: plan,
            permit: permit,
            revision: revision,
            cacheRoot: cacheRoot
        )
    }
}
