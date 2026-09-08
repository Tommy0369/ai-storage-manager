import Foundation
import SafetyCore

/// Presentation overlay for the physical tree. Does not infer Safety.
public enum StorageExplorerBuilder {
    public static func structureSnapshot(
        physicalRoot: PhysicalStorageNode,
        stats: PhysicalHierarchyStats,
        disk: DiskCapacitySnapshot,
        telemetry: StorageExplorerTelemetry,
        snapshotID: String = UUID().uuidString
    ) -> StorageExplorerSnapshot {
        let accounting = PhysicalMapAccountingResolver.resolve(for: physicalRoot)
        let presented = present(
            node: physicalRoot,
            itemsByPath: [:],
            decisionsByPath: [:],
            structureKey: physicalRoot.id
        )
        var telemetry = telemetry
        telemetry.physicalNodeCount = max(telemetry.physicalNodeCount, stats.physicalNodeCount)
        telemetry.maxDepth = max(telemetry.maxDepth, stats.maxDepth)
        telemetry.renderedNodeCount = max(telemetry.renderedNodeCount, stats.physicalNodeCount)
        telemetry.largestFanout = max(telemetry.largestFanout, stats.largestFanout)
        return StorageExplorerSnapshot(
            snapshotID: snapshotID,
            diskCapacity: disk,
            physicalRoot: physicalRoot,
            presentedRoot: presented,
            insights: [],
            scanStage: .hierarchyAvailable,
            telemetry: telemetry,
            uniqueClassifiedBytes: 0,
            unclassifiedBytes: 0,
            physicalMapBytes: accounting.reportMappedBytes,
            mapAccounting: accounting,
            accountingValid: accounting.accountingValid && !stats.duplicateByteOwnership,
            structureLensAvailable: true,
            meaningLensAvailable: false,
            decisionLensAvailable: false,
            mapReadiness: accounting.coverage == .complete ? .structureReadyMeasured : .structureReadyPartial,
            generation: 1
        )
    }

    public static func enrich(
        _ snapshot: StorageExplorerSnapshot,
        report: ReadOnlyAnalysisReport?,
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        history: [UIActionHistoryItem],
        insights: [StorageInsight],
        stage: StorageScanStage
    ) -> StorageExplorerSnapshot {
        let itemsByPath = pathIndex(report)
        let decisions = decisionIndex(safe: safe, review: review, protected: protected, history: history)
        let physical = overlaySemantics(snapshot.physicalRoot, itemsByPath: itemsByPath)
        let accounting = PhysicalMapAccountingResolver.resolve(for: physical)
        let presented = present(
            node: physical,
            itemsByPath: itemsByPath,
            decisionsByPath: decisions,
            structureKey: physical.id
        )
        var copy = snapshot
        copy.physicalRoot = physical
        copy.presentedRoot = presented
        copy.insights = insights
        copy.scanStage = stage
        copy.uniqueClassifiedBytes = report?.byteAccounting.exclusiveTotal ?? snapshot.uniqueClassifiedBytes
        copy.unclassifiedBytes = report.map { max(0, $0.coverage.scannedBytes - $0.byteAccounting.exclusiveTotal) } ?? snapshot.unclassifiedBytes
        copy.meaningLensAvailable = report != nil
        copy.decisionLensAvailable = report != nil
        if report != nil {
            copy.mapReadiness = stage == .complete ? .complete : .decisionEnriched
        }
        copy.generation += 1
        copy.physicalMapBytes = accounting.reportMappedBytes
        copy.mapAccounting = accounting
        copy.accountingValid = accounting.accountingValid
            && !PhysicalHierarchyBuilder.hasDuplicateByteOwnership(physical)
        return copy
    }

    public static func node(withID id: String, in root: StorageNodePresentation) -> StorageNodePresentation? {
        if root.id == id { return root }
        for child in root.children {
            if let hit = node(withID: id, in: child) { return hit }
        }
        return nil
    }

    public static func pathTo(id: String, in root: StorageNodePresentation) -> [StorageNodePresentation]? {
        if root.id == id { return [root] }
        for child in root.children {
            if let sub = pathTo(id: id, in: child) {
                return [root] + sub
            }
        }
        return nil
    }

    public static func flatten(_ root: StorageNodePresentation) -> [StorageNodePresentation] {
        var out: [StorageNodePresentation] = [root]
        for child in root.children {
            out.append(contentsOf: flatten(child))
        }
        return out
    }

    public static func search(root: StorageNodePresentation, query: String) -> [StorageNodePresentation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        return flatten(root).filter { node in
            node.title.lowercased().contains(q)
                || node.location.lowercased().contains(q)
                || node.semanticCategory.displayName.lowercased().contains(q)
                || (node.technicalEntityID?.lowercased().contains(q) ?? false)
                || node.physical.canonicalPath.lowercased().contains(q)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    public static func largestItems(root: StorageNodePresentation, limit: Int = 40) -> [StorageNodePresentation] {
        flatten(root)
            .filter { !$0.physical.isAggregate && $0.id != root.id }
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { $0 }
    }

    public static func layoutArcs(focus: StorageNodePresentation, rings: Int = 3) -> [SunburstArc] {
        var arcs: [SunburstArc] = []
        let accounting = PhysicalMapAccountingResolver.resolve(for: focus.physical)
        let geometryTotal: Int64
        if let mapped = accounting.geometryBytes {
            geometryTotal = max(mapped, 1)
        } else if focus.physical.bytesKnown {
            geometryTotal = max(focus.bytes, 1)
        } else {
            geometryTotal = max(accounting.knownChildMappedBytes, 1)
        }
        let exclusive: Int64
        if focus.physical.bytesKnown, focus.physical.exclusiveKnown {
            exclusive = focus.physical.exclusiveBytes
        } else {
            exclusive = 0
        }
        layoutLevel(
            nodes: displayChildren(focus),
            start: -90,
            sweep: 360,
            ring: 0,
            maxRing: max(1, rings) - 1,
            parentBytes: geometryTotal,
            exclusive: exclusive,
            exclusiveID: focus.id + "#self",
            into: &arcs
        )
        return arcs
    }

    public static func report(from snapshot: StorageExplorerSnapshot, falseGREEN: Int, duplicateEvaluations: Int) -> P301StorageExplorerReport {
        let stats = snapshot.telemetry
        let accounting = snapshot.mapAccounting ?? PhysicalMapAccountingResolver.resolve(for: snapshot.physicalRoot)
        return P301StorageExplorerReport(
            diskTotalBytes: snapshot.diskCapacity.volumeTotalBytes,
            diskUsedBytes: snapshot.diskCapacity.volumeUsedBytes,
            diskFreeBytes: snapshot.diskCapacity.volumeAvailableBytes,
            physicalMapBytes: accounting.reportMappedBytes,
            physicalMapAccountingBasis: accounting.basis.rawValue,
            physicalMapCoverage: accounting.coverage.rawValue,
            rootMeasurementStatus: accounting.rootMeasurementStatus.rawValue,
            rootMeasuredBytes: accounting.rootMeasuredBytes,
            rootTotalKnown: accounting.rootTotalKnown,
            knownChildMappedBytes: accounting.knownChildMappedBytes,
            fallbackUsed: accounting.fallbackUsed,
            unknownRemainderKnown: accounting.unknownRemainderKnown,
            uniqueClassifiedBytes: snapshot.uniqueClassifiedBytes,
            unclassifiedBytes: snapshot.unclassifiedBytes,
            physicalNodeCount: stats.physicalNodeCount,
            maxHierarchyDepth: stats.maxDepth,
            structureLensAvailable: snapshot.structureLensAvailable,
            meaningLensAvailable: snapshot.meaningLensAvailable,
            decisionLensAvailable: snapshot.decisionLensAvailable,
            quickLookAvailable: true,
            searchAvailable: true,
            breadcrumbAvailable: true,
            accountingValid: snapshot.accountingValid,
            falseGREEN: falseGREEN,
            duplicateEvaluations: duplicateEvaluations,
            generatedAt: snapshot.generatedAt
        )
    }

    public static func performanceReport(from snapshot: StorageExplorerSnapshot) -> P301ExplorerPerformanceReport {
        let t = snapshot.telemetry
        let accounting = snapshot.mapAccounting ?? PhysicalMapAccountingResolver.resolve(for: snapshot.physicalRoot)
        return P301ExplorerPerformanceReport(
            timeToFirstHierarchyMs: t.timeToFirstHierarchyMs,
            timeToFirstUsefulMapMs: t.timeToFirstUsefulMapMs,
            timeToSemanticEnrichmentMs: t.timeToSemanticEnrichmentMs,
            timeToSafetyEnrichmentMs: t.timeToSafetyEnrichmentMs,
            physicalNodeCount: t.physicalNodeCount,
            maxDepth: t.maxDepth,
            renderedNodeCount: t.renderedNodeCount,
            largestFanout: t.largestFanout,
            rootMeasurementTimedOut: accounting.rootMeasurementStatus == .timeout,
            fallbackAccountingUsed: accounting.fallbackUsed,
            generatedAt: snapshot.generatedAt
        )
    }

    public static func stories(from snapshot: StorageExplorerSnapshot) -> [String] {
        var lines: [String] = []
        if let top = snapshot.presentedRoot.children.max(by: { $0.bytes < $1.bytes }), top.bytesKnown {
            lines.append(L10n.t("story.largestFolder", top.title, UICandidateMapper.byteLabel(top.bytes)))
        }
        if let insight = snapshot.insights.first {
            lines.append(insight.title)
        }
        return lines
    }

    // MARK: - Internals

    private static func displayChildren(_ node: StorageNodePresentation) -> [StorageNodePresentation] {
        node.children.filter { $0.bytesKnown && $0.bytes > 0 && !$0.physical.isRestricted }
    }

    private static func layoutLevel(
        nodes: [StorageNodePresentation],
        start: Double,
        sweep: Double,
        ring: Int,
        maxRing: Int,
        parentBytes: Int64,
        exclusive: Int64,
        exclusiveID: String,
        into arcs: inout [SunburstArc]
    ) {
        var pieces: [(id: String, title: String, bytes: Int64, node: StorageNodePresentation?)] = nodes.map {
            ($0.id, $0.title, $0.bytes, $0)
        }
        if exclusive > 0 {
            pieces.append((exclusiveID, L10n.t("map.inThisFolder"), exclusive, nil))
        }
        let total = pieces.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > 0, sweep > 0.05 else { return }
        var cursor = start
        for piece in pieces {
            let fraction = Double(piece.bytes) / Double(total)
            let span = sweep * fraction
            guard span > 0.08 else {
                cursor += span
                continue
            }
            arcs.append(
                SunburstArc(
                    id: "\(ring):\(piece.id)",
                    nodeID: piece.id,
                    ringIndex: ring,
                    startDegrees: cursor,
                    endDegrees: cursor + span,
                    title: piece.title,
                    bytes: piece.bytes
                )
            )
            if ring < maxRing, let node = piece.node {
                layoutLevel(
                    nodes: displayChildren(node),
                    start: cursor,
                    sweep: span,
                    ring: ring + 1,
                    maxRing: maxRing,
                    parentBytes: max(piece.bytes, 1),
                    exclusive: node.physical.exclusiveKnown ? node.physical.exclusiveBytes : 0,
                    exclusiveID: node.id + "#self",
                    into: &arcs
                )
            }
            cursor += span
        }
    }

    private static func pathIndex(_ report: ReadOnlyAnalysisReport?) -> [String: ClassifiedItem] {
        guard let report else { return [:] }
        var map: [String: ClassifiedItem] = [:]
        for item in report.items {
            let key = (item.detected.entity.path as NSString).standardizingPath
            map[key] = item
        }
        return map
    }

    private static func decisionIndex(
        safe: [UICandidateItem],
        review: [UICandidateItem],
        protected: [UICandidateItem],
        history: [UIActionHistoryItem]
    ) -> [String: StorageNodeDecisionSummary] {
        var map: [String: StorageNodeDecisionSummary] = [:]
        for item in protected {
            map[standardized(item.fullPath)] = StorageNodeDecisionSummary(
                state: .protected,
                label: "Protected",
                iconHint: "lock.fill",
                entityID: item.entityID,
                source: "canonical_action_decision"
            )
        }
        for item in review {
            map[standardized(item.fullPath)] = StorageNodeDecisionSummary(
                state: .verificationNeeded,
                label: "Needs verification",
                iconHint: "questionmark.circle",
                entityID: item.entityID,
                source: "canonical_action_decision"
            )
        }
        for item in safe {
            map[standardized(item.fullPath)] = StorageNodeDecisionSummary(
                state: .readyToOptimize,
                label: "Ready",
                iconHint: "checkmark.circle",
                entityID: item.entityID,
                source: "canonical_action_decision"
            )
        }
        for item in history where item.storageRecoveryPending {
            map[standardized(item.entityID)] = StorageNodeDecisionSummary(
                state: .recoveryPending,
                label: "Recovery pending",
                iconHint: "clock",
                entityID: item.entityID,
                source: "canonical_action_decision"
            )
        }
        return map
    }

    private static func overlaySemantics(_ node: PhysicalStorageNode, itemsByPath: [String: ClassifiedItem]) -> PhysicalStorageNode {
        var copy = node
        if let item = longestMatch(path: node.canonicalPath, in: itemsByPath) {
            let pres = EntityPresentationResolver.resolve(item: item)
            copy.semanticEntityID = item.detected.entity.id
            copy.semanticCategoryRaw = pres.category.rawValue
        }
        copy.children = node.children.map { overlaySemantics($0, itemsByPath: itemsByPath) }
        return copy
    }

    private static func present(
        node: PhysicalStorageNode,
        itemsByPath: [String: ClassifiedItem],
        decisionsByPath: [String: StorageNodeDecisionSummary],
        structureKey: String
    ) -> StorageNodePresentation {
        let item = longestMatch(path: node.canonicalPath, in: itemsByPath)
        let pres = item.map { EntityPresentationResolver.resolve(item: $0) }
        let category = pres?.category
            ?? ProductStorageCategory(rawValue: node.semanticCategoryRaw ?? "")
            ?? inferCategoryFromPath(node.canonicalPath)
        let title: String
        if node.isRestricted || node.displayName == "Restricted / Not Scanned" {
            title = L10n.t("entity.restrictedNotScanned.title")
        } else if let item, let pres, standardized(item.detected.entity.path) == standardized(node.canonicalPath) {
            title = pres.title
        } else if node.isAggregate || node.displayName == "Other smaller items" {
            title = L10n.t("map.otherSmallerItems")
        } else {
            title = node.displayName
        }
        let what: String
        if node.isRestricted {
            what = L10n.t("entity.restrictedNotScanned.what")
        } else if let pres {
            what = pres.description
        } else if node.nodeKind == .file {
            what = L10n.t("entity.generic.file")
        } else if node.nodeKind == .package {
            what = L10n.t("entity.generic.package")
        } else if node.nodeKind == .symlink {
            what = L10n.t("entity.generic.symlink")
        } else if node.isAggregate {
            what = L10n.t("entity.generic.aggregate")
        } else {
            what = L10n.t("entity.generic.unidentified")
        }
        let why = whyLarge(node: node, presentation: pres)
        let decision = decisionsByPath[standardized(node.canonicalPath)]
            ?? item.flatMap { decisionsByPath[standardized($0.detected.entity.path)] }
            ?? .none
        let childKeyBase = structureKey
        let children = node.children.map { child in
            present(
                node: child,
                itemsByPath: itemsByPath,
                decisionsByPath: decisionsByPath,
                structureKey: node.depth == 0 ? child.id : childKeyBase
            )
        }
        return StorageNodePresentation(
            id: node.id,
            physical: node,
            title: title,
            location: node.canonicalPath.replacingOccurrences(of: "/#other", with: ""),
            whatIsThis: what,
            whyLarge: why,
            semanticCategory: category,
            decision: decision,
            children: children,
            technicalEntityID: item?.detected.entity.id ?? node.semanticEntityID,
            structureColorKey: node.depth == 0 ? node.id : structureKey
        )
    }

    private static func whyLarge(node: PhysicalStorageNode, presentation: EntityPresentationResolver.Presentation?) -> String? {
        if let why = presentation?.whyLarge { return why }
        let large = node.children.filter(\.bytesKnown).sorted { $0.bytes > $1.bytes }.prefix(3)
        if !large.isEmpty {
            let names = large.map { childDisplayName($0) }.joined(separator: ", ")
            return L10n.t("map.containsLargeChildren", names)
        }
        switch presentation?.category {
        case .aiTools: return L10n.t("map.containsAIModels")
        case .developer: return L10n.t("map.containsDeveloper")
        case .macOSSystem: return L10n.t("map.containsAppSupport")
        case .cloud: return L10n.t("map.containsCloud")
        default: return nil
        }
    }

    private static func childDisplayName(_ node: PhysicalStorageNode) -> String {
        if node.isAggregate || node.displayName == "Other smaller items" {
            return L10n.t("map.otherSmallerItems")
        }
        return node.displayName
    }

    private static func inferCategoryFromPath(_ path: String) -> ProductStorageCategory {
        let lower = path.lowercased()
        if lower.contains("/.ollama") || lower.contains("huggingface") || lower.contains("/.claude") || lower.contains("/cursor") {
            return .aiTools
        }
        if lower.contains("deriveddata") || lower.contains("/developer/") { return .developer }
        if lower.contains("/library/") { return .macOSSystem }
        if lower.contains("/documents") || lower.contains("/desktop") || lower.contains("/downloads") {
            return .personalFiles
        }
        if lower.contains("/applications") { return .applications }
        if lower.contains("mobilesync") { return .backups }
        return .otherUnknown
    }

    private static func longestMatch(path: String, in items: [String: ClassifiedItem]) -> ClassifiedItem? {
        let key = standardized(path)
        if let exact = items[key] { return exact }
        var best: (Int, ClassifiedItem)?
        for (itemPath, item) in items {
            if key.hasPrefix(itemPath + "/") || itemPath.hasPrefix(key + "/") {
                let score = min(itemPath.count, key.count)
                if best == nil || score > best!.0 {
                    best = (score, item)
                }
            }
        }
        return best?.1
    }

    private static func standardized(_ path: String) -> String {
        (PathGlob.expandHome(path) as NSString).standardizingPath
    }
}

