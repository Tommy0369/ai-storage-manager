import Foundation
import SafetyCore

/// Builds presentation snapshot from P3 report JSON for previews and screenshot export.
public enum PreviewSnapshotFactory {
    public static func fromP30Report(
        _ report: P30StorageExperienceReport,
        volumeName: String = "Macintosh HD"
    ) -> StorageExperienceSnapshot {
        let categories = report.topCategories.compactMap { row -> StorageMapNode? in
            guard let name = row["name"], let bytesStr = row["bytes"], let bytes = Int64(bytesStr) else { return nil }
            let catRaw = row["category"] ?? ProductStorageCategory.otherUnknown.rawValue
            let category = ProductStorageCategory(rawValue: catRaw) ?? .otherUnknown
            return StorageMapNode(
                id: "category.\(category.rawValue)",
                title: name,
                bytes: bytes,
                semanticCategory: category,
                isAggregate: true,
                iconHint: category.iconHint
            )
        }
        let mapRoot = StorageMapNode(
            id: "map.root",
            title: volumeName,
            subtitle: "Unique classified storage",
            bytes: report.mapRootBytes,
            children: categories,
            semanticCategory: .otherUnknown,
            isAggregate: true,
            iconHint: "internaldrive"
        )
        let insights: [StorageInsight] = [
            StorageInsight(
                id: "insight.ai",
                kind: .largeStorageDriver,
                title: categories.first.map { "\($0.title) is using \(UICandidateMapper.byteLabel($0.bytes))." } ?? "Large storage driver detected",
                message: "Most of this space may be protected until we can prove it can be safely recreated.",
                bytes: categories.first?.bytes,
                category: categories.first?.semanticCategory
            ),
            StorageInsight(
                id: "insight.verify",
                kind: .verificationNeeded,
                title: "\(report.needsReviewCount) need verification",
                message: "We need more evidence before recommending action on these items.",
                bytes: report.needsReviewBytes,
                category: nil
            ),
        ]
        return StorageExperienceSnapshot(
            diskCapacity: DiskCapacitySnapshot(
                volumeName: volumeName,
                volumeTotalBytes: report.diskTotalBytes,
                volumeAvailableBytes: report.diskAvailableBytes,
                volumeUsedBytes: report.diskUsedBytes
            ),
            observedStorage: ObservedStorageSnapshot(
                scannedRootBytes: report.observedBytes,
                classifiedUniqueBytes: report.mapRootBytes,
                unclassifiedBytes: report.unclassifiedBytes,
                selectedRootLabel: volumeName
            ),
            mapRoot: mapRoot,
            categories: categories,
            insights: insights,
            recommendations: [],
            needsReview: [],
            protected: [],
            recentActions: [],
            readyActionCount: report.readyActionCount,
            readyPotentialBytes: report.readyPotentialBytes,
            needsReviewCount: report.needsReviewCount,
            needsReviewBytes: report.needsReviewBytes,
            protectedCount: report.protectedCount,
            protectedBytes: report.protectedBytes,
            recoveryPendingBytes: report.recoveryPendingBytes,
            mapAccountingValid: report.mapAccountingValid,
            mapRootBytes: report.mapRootBytes,
            generatedAt: report.generatedAt,
            scanRuntimeSeconds: nil
        )
    }

    public static func loadCase001(from directory: URL) throws -> StorageExperienceSnapshot {
        let url = directory.appendingPathComponent("p3_0_storage_experience.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(P30StorageExperienceReport.self, from: data)
        return fromP30Report(report)
    }

    public static func loadCase001Explorer(from directory: URL) throws -> StorageExplorerSnapshot {
        let experience = try loadCase001(from: directory)
        return explorerDemo(experience: experience)
    }

    public static func explorerDemo(experience: StorageExperienceSnapshot? = nil) -> StorageExplorerSnapshot {
        let disk = experience?.diskCapacity ?? DiskCapacitySnapshot(
            volumeName: "Macintosh HD",
            volumeTotalBytes: 494_384_003_072,
            volumeAvailableBytes: 146_893_113_116,
            volumeUsedBytes: 347_439_253_732
        )
        let physical = demoPhysicalTree(volumeName: disk.volumeName.isEmpty ? "Macintosh HD" : disk.volumeName)
        let accounting = PhysicalMapAccountingResolver.resolve(for: physical)
        let stats = PhysicalHierarchyStats(
            physicalNodeCount: PhysicalHierarchyBuilder.flatten(physical).count,
            maxDepth: PhysicalHierarchyBuilder.flatten(physical).map(\.depth).max() ?? 0,
            largestFanout: PhysicalHierarchyBuilder.flatten(physical).map(\.children.count).max() ?? 0,
            representedBytes: accounting.reportMappedBytes,
            restrictedNodeCount: PhysicalHierarchyBuilder.flatten(physical).filter(\.isRestricted).count,
            unknownByteNodeCount: PhysicalHierarchyBuilder.flatten(physical).filter { !$0.bytesKnown }.count,
            accountingValid: accounting.accountingValid,
            duplicateByteOwnership: PhysicalHierarchyBuilder.hasDuplicateByteOwnership(physical),
            timeToFirstHierarchyMs: 420
        )
        var telemetry = StorageExplorerTelemetry(
            scanStartedAt: Date().addingTimeInterval(-12),
            firstHierarchyAvailableAt: Date().addingTimeInterval(-11.5),
            firstMapRenderedAt: Date().addingTimeInterval(-11.4),
            semanticEnrichmentCompleteAt: Date().addingTimeInterval(-2),
            safetyAnalysisCompleteAt: Date(),
            timeToFirstHierarchyMs: stats.timeToFirstHierarchyMs,
            timeToFirstUsefulMapMs: stats.timeToFirstHierarchyMs,
            timeToSemanticEnrichmentMs: 10_200,
            timeToSafetyEnrichmentMs: 12_000,
            physicalNodeCount: stats.physicalNodeCount,
            maxDepth: stats.maxDepth,
            renderedNodeCount: stats.physicalNodeCount,
            largestFanout: stats.largestFanout
        )
        _ = telemetry
        let structure = StorageExplorerBuilder.structureSnapshot(
            physicalRoot: physical,
            stats: stats,
            disk: disk,
            telemetry: StorageExplorerTelemetry(
                timeToFirstHierarchyMs: 420,
                timeToFirstUsefulMapMs: 420,
                timeToSemanticEnrichmentMs: 10_200,
                timeToSafetyEnrichmentMs: 12_000,
                physicalNodeCount: stats.physicalNodeCount,
                maxDepth: stats.maxDepth,
                renderedNodeCount: stats.physicalNodeCount,
                largestFanout: stats.largestFanout
            )
        )
        var enriched = StorageExplorerBuilder.enrich(
            structure,
            report: nil,
            safe: [
                UICandidateItem(
                    id: "safe.derived",
                    entityID: "xcode.deriveddata.fixture",
                    displayName: "Xcode Build Data",
                    category: "Developer",
                    pathSummary: "DerivedData",
                    fullPath: "/Users/demo/Library/Developer/Xcode/DerivedData",
                    byteLabel: "7.5 GB",
                    expectedBytes: 7_500_000_000,
                    recommendedAction: .moveToTrash,
                    recommendedActionLabel: "Move to Trash",
                    reasonSummary: "Regenerable build data",
                    readiness: .approvalRequired,
                    group: .safeActions,
                    safetyClass: .green,
                    evidenceLines: [],
                    executorAvailable: true
                )
            ],
            review: [],
            protected: [
                UICandidateItem(
                    id: "prot.claude",
                    entityID: "ai.claude",
                    displayName: "Claude Data",
                    category: "AI Tools",
                    pathSummary: "Claude",
                    fullPath: "/Users/demo/Library/Application Support/Claude",
                    byteLabel: "4.1 GB",
                    expectedBytes: 4_100_000_000,
                    recommendedAction: nil,
                    recommendedActionLabel: "Protected",
                    reasonSummary: "Protected runtime data",
                    readiness: .unknown,
                    group: .protected,
                    safetyClass: .red,
                    evidenceLines: [],
                    executorAvailable: false
                )
            ],
            history: [],
            insights: experience?.insights ?? [
                StorageInsight(
                    id: "story.ai",
                    kind: .largeStorageDriver,
                    title: "AI tools are your largest understood category: 48.6 GB.",
                    message: "This is classified unique storage, not the whole disk.",
                    bytes: 48_646_426_624,
                    category: .aiTools
                ),
                StorageInsight(
                    id: "story.sys",
                    kind: .protectedImportant,
                    title: "38.8 GB is macOS/system-related and mostly protected.",
                    message: "Protected areas stay protected until evidence changes.",
                    bytes: 38_769_496_064,
                    category: .macOSSystem
                ),
                StorageInsight(
                    id: "story.review",
                    kind: .verificationNeeded,
                    title: "\(experience?.needsReviewCount ?? 56) items need more verification.",
                    message: "Actions stay unavailable until verification completes.",
                    bytes: experience?.needsReviewBytes,
                    category: nil
                ),
            ],
            stage: .complete
        )
        enriched.meaningLensAvailable = true
        enriched.decisionLensAvailable = true
        enriched.uniqueClassifiedBytes = experience?.mapRootBytes ?? 105_802_498_048
        enriched.unclassifiedBytes = experience?.observedStorage.unclassifiedBytes ?? 0
        return enriched
    }

    public static func demoPhysicalTree(volumeName: String = "Macintosh HD") -> PhysicalStorageNode {
        let home = "/Users/demo"
        func node(
            _ name: String,
            _ rel: String,
            _ bytes: Int64,
            kind: PhysicalNodeKind = .directory,
            category: String? = nil,
            entity: String? = nil,
            depth: Int,
            children: [PhysicalStorageNode] = []
        ) -> PhysicalStorageNode {
            let path = rel.hasPrefix("/") ? rel : home + "/" + rel
            let childSum = children.reduce(Int64(0)) { $0 + ($1.bytesKnown ? $1.bytes : 0) }
            return PhysicalStorageNode(
                id: "phys:" + path,
                canonicalPath: path,
                displayName: name,
                nodeKind: kind,
                bytes: bytes,
                bytesKnown: true,
                exclusiveBytes: max(Int64(0), bytes - childSum),
                exclusiveKnown: true,
                children: children,
                depth: depth,
                isDirectory: kind == .directory || kind == .volume || kind == .otherAggregate,
                isFile: kind == .file,
                isPackage: kind == .package,
                isSymlink: kind == .symlink,
                semanticEntityID: entity,
                semanticCategoryRaw: category
            )
        }

        let derived = node("DerivedData", "Library/Developer/Xcode/DerivedData", 7_500_000_000, category: "DEVELOPER", entity: "xcode.deriveddata.fixture", depth: 4)
        let xcode = node("Xcode", "Library/Developer/Xcode", 7_900_000_000, category: "DEVELOPER", depth: 3, children: [derived])
        let developer = node("Developer", "Library/Developer", 7_900_000_000, category: "DEVELOPER", depth: 2, children: [xcode])
        let cursor = node("Cursor", "Library/Application Support/Cursor", 8_200_000_000, category: "AI_TOOLS", entity: "ai.cursor", depth: 3)
        let claude = node("Claude", "Library/Application Support/Claude", 4_100_000_000, category: "AI_TOOLS", entity: "ai.claude", depth: 3)
        let otherAS = node(
            "Other smaller items",
            "Library/Application Support/#other",
            5_400_000_000,
            kind: .otherAggregate,
            depth: 3,
            children: [
                node("Slack", "Library/Application Support/Slack", 1_200_000_000, depth: 4),
                node("Chrome", "Library/Application Support/Google", 2_100_000_000, depth: 4),
            ]
        )
        let appSupport = node(
            "Application Support",
            "Library/Application Support",
            17_700_000_000,
            category: "MACOS_SYSTEM",
            depth: 2,
            children: [cursor, claude, otherAS]
        )
        let containers = node("Containers", "Library/Containers", 9_500_000_000, category: "MACOS_SYSTEM", depth: 2)
        let caches = node("Caches", "Library/Caches", 3_800_000_000, category: "MACOS_SYSTEM", depth: 2)
        let library = node(
            "Library",
            "Library",
            69_700_000_000,
            category: "MACOS_SYSTEM",
            depth: 1,
            children: [appSupport, containers, developer, caches]
        )
        let projects = node("Projects", "Documents/Projects", 10_000_000_000, category: "PERSONAL_FILES", depth: 2)
        let documents = node("Documents", "Documents", 14_000_000_000, category: "PERSONAL_FILES", depth: 1, children: [projects])
        let downloads = node("Downloads", "Downloads", 8_000_000_000, category: "PERSONAL_FILES", depth: 1)
        let movies = node("Movies", "Movies", 5_000_000_000, category: "PERSONAL_FILES", depth: 1)
        let pictures = node("Pictures", "Pictures", 4_000_000_000, category: "PERSONAL_FILES", depth: 1)
        let ollama = node(".ollama", ".ollama", 12_000_000_000, category: "AI_TOOLS", entity: "ai.ollama.blobs", depth: 1)
        let hf = node(".cache", ".cache", 8_400_000_000, category: "AI_TOOLS", entity: "ai.hf.hub", depth: 1)
        let restricted = PhysicalStorageNode(
            id: "phys:/System",
            canonicalPath: "/System",
            displayName: "Restricted / Not Scanned",
            nodeKind: .restricted,
            bytes: 0,
            bytesKnown: false,
            children: [],
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            isRestricted: true,
            measurementQuality: .unknown,
            measurementReason: "HARD_BLOCKED"
        )

        let childSum: Int64 = 69_700_000_000 + 14_000_000_000 + 8_000_000_000 + 5_000_000_000 + 4_000_000_000 + 12_000_000_000 + 8_400_000_000
        return node(
            volumeName,
            home,
            childSum,
            kind: .volume,
            depth: 0,
            children: [library, documents, downloads, movies, pictures, ollama, hf, restricted]
        )
    }
}
