import Foundation

/// P2.2 — Integrates post-mutation verification into scan lifecycle.
public enum PostMutationScanIntegration {
    public struct Bundle: Sendable, Equatable {
        public var registry: PendingPostMutationRegistryDocument
        public var verificationReport: PostMutationVerificationReport
        public var actionHistory: ActionHistoryReport
        public var storageRecoveryResults: [StorageRecoveryResult]
        public var summary: PostMutationScanSummary
    }

    public static func reconcile(
        scanItems: [ClassifiedItem],
        registryDirectory: URL? = nil,
        observedAt: Date = Date()
    ) -> Bundle {
        var registry: PendingPostMutationRegistryDocument
        if let dir = registryDirectory {
            registry = PendingPostMutationRegistry.load(from: dir)
        } else {
            registry = .empty
        }

        registry = PendingPostMutationRegistry.reconcile(
            registry: registry,
            scanItems: scanItems,
            registryDirectory: registryDirectory,
            observedAt: observedAt
        )

        if let dir = registryDirectory {
            try? PendingPostMutationRegistry.save(registry, to: dir)
        }

        let executionReport = registryDirectory.flatMap {
            PendingPostMutationRegistry.loadExecutionReport(from: $0)
        }
        let actionHistory = PendingPostMutationRegistry.buildActionHistory(
            registry: registry,
            executionReport: executionReport
        )
        let storageRecovery = registry.closed.map { PostMutationVerifier.storageRecovery(from: $0) }
        let summary = PendingPostMutationRegistry.formatScanSummary(
            results: registry.closed,
            pending: registry.pending
        )
        let verificationReport = PostMutationVerificationReport(
            results: registry.closed,
            pendingCount: registry.pending.count,
            closedCount: registry.closed.count,
            generatedAt: observedAt
        )

        return Bundle(
            registry: registry,
            verificationReport: verificationReport,
            actionHistory: actionHistory,
            storageRecoveryResults: storageRecovery,
            summary: summary
        )
    }
}
