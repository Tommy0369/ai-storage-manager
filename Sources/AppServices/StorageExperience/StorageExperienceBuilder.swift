import Foundation
import SafetyCore

/// Builds immutable presentation snapshot from canonical scan. Does NOT infer Safety.
public enum StorageExperienceBuilder {
    public static func build(
        report: ReadOnlyAnalysisReport,
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        history: [UIActionHistoryItem],
        volumePath: String = NSHomeDirectory()
    ) -> StorageExperienceSnapshot {
        let disk = DiskCapacityReader.snapshot(at: volumePath)
        let scanned = report.coverage.scannedBytes
        let mapBytes = report.byteAccounting.exclusiveTotal

        let gateByEntity = Dictionary(
            report.mutationGate.entries
                .filter { $0.action == StorageAction.moveToTrash.rawValue }
                .map { ($0.entityID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        var categoryBuckets: [ProductStorageCategory: [ClassifiedItem]] = [:]
        for item in report.items {
            let cat = EntityPresentationResolver.resolve(item: item).category
            categoryBuckets[cat, default: []].append(item)
        }

        let categories = ProductStorageCategory.allCases.compactMap { cat -> StorageMapNode? in
            guard let items = categoryBuckets[cat], !items.isEmpty else { return nil }
            return buildCategoryNode(category: cat, items: items, gateByEntity: gateByEntity, safe: safe, review: review, protected: protected)
        }.sorted { $0.bytes > $1.bytes }

        var rootChildren = categories
        let categorySum = categories.reduce(Int64(0)) { $0 + $1.bytes }
        let unclassified = max(0, mapBytes - categorySum)
        if unclassified > 0 {
            rootChildren.append(
                StorageMapNode(
                    id: "category.other_unknown",
                    title: ProductStorageCategory.otherUnknown.displayName,
                    subtitle: "Bytes not yet attributed to a category",
                    bytes: unclassified,
                    semanticCategory: .otherUnknown,
                    presentationState: .noRecommendation,
                    isAggregate: true,
                    iconHint: ProductStorageCategory.otherUnknown.iconHint
                )
            )
        }

        let rootTitle = disk.volumeName.isEmpty ? "Macintosh HD" : disk.volumeName
        let mapRoot = StorageMapNode(
            id: "map.root",
            title: rootTitle,
            subtitle: "Unique classified storage",
            bytes: mapBytes,
            children: rootChildren,
            semanticCategory: .otherUnknown,
            presentationState: .informational,
            isAggregate: true,
            iconHint: "internaldrive"
        )

        let mapAccountingValid = categorySum + unclassified == mapBytes

        let recommendations = buildRecommendations(safe: safe, report: report, gateByEntity: gateByEntity)
        let needsReview = buildReviewItems(review: review, report: report, gateByEntity: gateByEntity)
        let protectedItems = buildProtectedItems(protected: protected, report: report)
        let insights = buildInsights(
            categories: categories,
            safe: safe,
            review: review,
            protected: protected,
            history: history,
            report: report
        )

        let readyBytes = safe.reduce(Int64(0)) { $0 + ($1.expectedBytes ?? 0) }
        let reviewBytes = review.reduce(Int64(0)) { $0 + ($1.expectedBytes ?? 0) }
        let protectedBytes = protected.reduce(Int64(0)) { $0 + ($1.expectedBytes ?? 0) }
        let recoveryPending = history.filter(\.storageRecoveryPending).reduce(Int64(0)) { partial, item in
            partial + (report.items.first { $0.detected.entity.id == item.entityID }?.exclusiveBytes ?? 0)
        }

        return StorageExperienceSnapshot(
            diskCapacity: disk,
            observedStorage: ObservedStorageSnapshot(
                scannedRootBytes: scanned,
                classifiedUniqueBytes: mapBytes,
                unclassifiedBytes: unclassified,
                selectedRootLabel: rootTitle
            ),
            mapRoot: mapRoot,
            categories: categories,
            insights: insights,
            recommendations: recommendations,
            needsReview: needsReview,
            protected: protectedItems,
            recentActions: history,
            readyActionCount: safe.count,
            readyPotentialBytes: readyBytes,
            needsReviewCount: review.count,
            needsReviewBytes: reviewBytes,
            protectedCount: protected.count,
            protectedBytes: protectedBytes,
            recoveryPendingBytes: recoveryPending,
            mapAccountingValid: mapAccountingValid,
            mapRootBytes: mapBytes,
            generatedAt: Date(),
            scanRuntimeSeconds: report.scanRuntimeSeconds
        )
    }

    public static func validateAccounting(
        categories: [StorageMapNode],
        scannedBytes: Int64,
        unclassifiedBytes: Int64
    ) -> Bool {
        let categorySum = categories.reduce(Int64(0)) { $0 + $1.bytes }
        return categorySum + unclassifiedBytes == scannedBytes
    }

    public static func report(from snapshot: StorageExperienceSnapshot) -> P30StorageExperienceReport {
        let topCategories = snapshot.categories.prefix(5).map { node -> [String: String] in
            [
                "name": node.title,
                "bytes": String(node.bytes),
                "category": node.semanticCategory.rawValue,
            ]
        }
        let topEntities = flattenEntities(snapshot.mapRoot).prefix(10).map { node -> [String: String] in
            [
                "title": node.title,
                "bytes": String(node.bytes),
                "entityID": node.technicalEntityID ?? node.entityID ?? node.id,
            ]
        }
        return P30StorageExperienceReport(
            diskTotalBytes: snapshot.diskCapacity.volumeTotalBytes,
            diskUsedBytes: snapshot.diskCapacity.volumeUsedBytes,
            diskAvailableBytes: snapshot.diskCapacity.volumeAvailableBytes,
            observedBytes: snapshot.observedStorage.scannedRootBytes,
            mapRootBytes: snapshot.mapRootBytes,
            unclassifiedBytes: snapshot.observedStorage.unclassifiedBytes,
            topCategories: topCategories,
            topEntities: topEntities,
            readyActionCount: snapshot.readyActionCount,
            readyPotentialBytes: snapshot.readyPotentialBytes,
            needsReviewCount: snapshot.needsReviewCount,
            needsReviewBytes: snapshot.needsReviewBytes,
            protectedCount: snapshot.protectedCount,
            protectedBytes: snapshot.protectedBytes,
            recoveryPendingBytes: snapshot.recoveryPendingBytes,
            recentActionCount: snapshot.recentActions.count,
            mapAccountingValid: snapshot.mapAccountingValid,
            technicalIDsHiddenByDefault: true,
            generatedAt: snapshot.generatedAt
        )
    }

    // MARK: - Internals

    private static func buildCategoryNode(
        category: ProductStorageCategory,
        items: [ClassifiedItem],
        gateByEntity: [String: MutationGateResult],
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem]
    ) -> StorageMapNode {
        let totalBytes = items.reduce(Int64(0)) { $0 + max(0, $1.exclusiveBytes) }
        let sorted = items.sorted { $0.exclusiveBytes > $1.exclusiveBytes }
        let top = sorted.prefix(10)
        let children = top.map { item -> StorageMapNode in
            let pres = EntityPresentationResolver.resolve(item: item)
            let entityID = item.detected.entity.id
            return StorageMapNode(
                id: "entity.\(entityID)",
                entityID: entityID,
                title: pres.title,
                subtitle: pres.subtitle,
                bytes: item.exclusiveBytes,
                semanticCategory: pres.category,
                presentationState: presentationState(
                    entityID: entityID,
                    safe: safe,
                    review: review,
                    protected: protected
                ),
                actionSummary: actionSummary(entityID: entityID, safe: safe),
                isAggregate: false,
                pathSummary: item.detected.entity.path,
                iconHint: pres.category.iconHint,
                technicalEntityID: entityID
            )
        }
        let remainder = sorted.dropFirst(10)
        var allChildren = children
        if !remainder.isEmpty {
            let restBytes = remainder.reduce(Int64(0)) { $0 + max(0, $1.exclusiveBytes) }
            allChildren.append(
                StorageMapNode(
                    id: "category.\(category.rawValue).other",
                    title: "Other in \(category.displayName)",
                    bytes: restBytes,
                    children: [],
                    semanticCategory: category,
                    presentationState: .informational,
                    isAggregate: true,
                    iconHint: category.iconHint
                )
            )
        }
        return StorageMapNode(
            id: "category.\(category.rawValue)",
            title: category.displayName,
            bytes: totalBytes,
            children: allChildren,
            semanticCategory: category,
            presentationState: .informational,
            isAggregate: true,
            iconHint: category.iconHint
        )
    }

    private static func presentationState(
        entityID: String,
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem]
    ) -> StoragePresentationState {
        if safe.contains(where: { $0.entityID == entityID }) { return .readyToOptimize }
        if review.contains(where: { $0.entityID == entityID }) { return .verificationNeeded }
        if protected.contains(where: { $0.entityID == entityID }) { return .protected }
        return .noRecommendation
    }

    private static func actionSummary(entityID: String, safe: [UICandidateItem]) -> String? {
        safe.first { $0.entityID == entityID }?.recommendedActionLabel
    }

    private static func buildRecommendations(
        safe: [UICandidateItem],
        report: ReadOnlyAnalysisReport,
        gateByEntity: [String: MutationGateResult]
    ) -> [RecommendationCard] {
        safe.compactMap { ui in
            guard ui.group == .safeActions else { return nil }
            guard ui.safetyClass != .unknown, ui.safetyClass != .red else { return nil }
            guard ui.readiness == .approvalRequired || ui.readiness == .preflightRequired else { return nil }
            let item = report.items.first { $0.detected.entity.id == ui.entityID }
            let pres = item.map { EntityPresentationResolver.resolve(item: $0) }
            let desc = pres?.description ?? ui.reasonSummary
            return RecommendationCard(
                id: ui.entityID,
                entityID: ui.entityID,
                title: pres?.title ?? ui.displayName,
                subtitle: pres?.subtitle ?? ui.category,
                bytes: ui.expectedBytes ?? 0,
                byteLabel: ui.byteLabel,
                description: desc,
                evidenceLines: ui.evidenceLines.map(\.userText),
                recommendedActionLabel: ui.recommendedActionLabel,
                potentialRecoveryLabel: "Potential local recovery: \(ui.byteLabel)",
                readiness: ui.readiness,
                technicalEntityID: ui.entityID,
                fullPath: ui.fullPath
            )
        }
    }

    private static func buildReviewItems(
        review: [UICandidateItem],
        report: ReadOnlyAnalysisReport,
        gateByEntity: [String: MutationGateResult]
    ) -> [ReviewItemPresentation] {
        review.map { ui in
            let item = report.items.first { $0.detected.entity.id == ui.entityID }
            let pres = item.map { EntityPresentationResolver.resolve(item: $0) }
            let reason = item.map {
                EntityPresentationResolver.reviewReason(item: $0, gate: gateByEntity[ui.entityID])
            } ?? ui.reasonSummary
            return ReviewItemPresentation(
                id: ui.entityID,
                entityID: ui.entityID,
                title: pres?.title ?? ui.displayName,
                bytes: ui.expectedBytes ?? 0,
                byteLabel: ui.byteLabel,
                reason: reason,
                category: pres?.category ?? .otherUnknown,
                technicalEntityID: ui.entityID
            )
        }
    }

    private static func buildProtectedItems(
        protected: [UICandidateItem],
        report: ReadOnlyAnalysisReport
    ) -> [ProtectedItemPresentation] {
        protected.map { ui in
            let item = report.items.first { $0.detected.entity.id == ui.entityID }
            let pres = item.map { EntityPresentationResolver.resolve(item: $0) }
            let explanation = item.map { EntityPresentationResolver.protectedExplanation(item: $0) } ?? ui.reasonSummary
            return ProtectedItemPresentation(
                id: ui.entityID,
                entityID: ui.entityID,
                title: pres?.title ?? ui.displayName,
                bytes: ui.expectedBytes ?? 0,
                byteLabel: ui.byteLabel,
                explanation: explanation,
                category: pres?.category ?? .otherUnknown,
                technicalEntityID: ui.entityID
            )
        }
    }

    private static func buildInsights(
        categories: [StorageMapNode],
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        history: [UIActionHistoryItem],
        report: ReadOnlyAnalysisReport
    ) -> [StorageInsight] {
        var insights: [StorageInsight] = []
        if let top = categories.first, top.bytes > 0 {
            insights.append(StorageInsight(
                id: "insight.top_category",
                kind: .largeStorageDriver,
                title: "\(top.title) is using \(UICandidateMapper.byteLabel(top.bytes)).",
                message: "This is one of the largest categories in the observed scan scope.",
                bytes: top.bytes,
                category: top.semanticCategory
            ))
        }
        if !safe.isEmpty {
            let bytes = safe.reduce(Int64(0)) { $0 + ($1.expectedBytes ?? 0) }
            insights.append(StorageInsight(
                id: "insight.safe_ready",
                kind: .safeActionReady,
                title: "\(safe.count) items ready",
                message: "These items passed safety checks and may be optimized when you review them.",
                bytes: bytes,
                category: nil
            ))
        }
        if !review.isEmpty {
            insights.append(StorageInsight(
                id: "insight.verify",
                kind: .verificationNeeded,
                title: "\(review.count) need verification",
                message: "We need more evidence before recommending action on these items.",
                bytes: review.reduce(0) { $0 + ($1.expectedBytes ?? 0) },
                category: nil
            ))
        }
        if protected.contains(where: { $0.category.lowercased().contains("backup") || $0.entityID.contains("backup") }) {
            insights.append(StorageInsight(
                id: "insight.protected_backup",
                kind: .protectedImportant,
                title: "Protected backups detected",
                message: "Device backups are important. Direct folder moves may make them unusable.",
                bytes: nil,
                category: .backups
            ))
        }
        if history.contains(where: { $0.storageRecoveryPending }) {
            insights.append(StorageInsight(
                id: "insight.recovery_pending",
                kind: .recoveryPending,
                title: "Disk recovery pending",
                message: "Some moved items remain in Trash and still use disk space.",
                bytes: nil,
                category: .trash
            ))
        }
        let aiTools = categories.first { $0.semanticCategory == .aiTools }
        if let aiTools, aiTools.bytes > 0 {
            insights.append(StorageInsight(
                id: "insight.ai_tools",
                kind: .largeStorageDriver,
                title: "AI development tools are using \(UICandidateMapper.byteLabel(aiTools.bytes)).",
                message: "Most of this space may be protected until we can prove it can be safely recreated.",
                bytes: aiTools.bytes,
                category: .aiTools
            ))
        }
        return insights
    }

    private static func flattenEntities(_ node: StorageMapNode) -> [StorageMapNode] {
        var result: [StorageMapNode] = []
        if !node.isAggregate, node.entityID != nil { result.append(node) }
        for child in node.children {
            result.append(contentsOf: flattenEntities(child))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }
}
