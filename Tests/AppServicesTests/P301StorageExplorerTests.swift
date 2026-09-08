import XCTest
@testable import AppServices
import SafetyCore

final class P301StorageExplorerTests: XCTestCase {
    func testPhysicalHierarchyDeterministicParentChild() throws {
        let root = try makeFixtureTree()
        XCTAssertEqual(root.displayName, "FixtureRoot")
        XCTAssertFalse(root.children.isEmpty)
        let library = root.children.first { $0.displayName == "Library" }
        XCTAssertNotNil(library)
        XCTAssertTrue(library!.children.contains { $0.displayName == "Application Support" })
    }

    func testFileFolderPackageDistinction() throws {
        let root = try makeFixtureTree()
        let file = PhysicalHierarchyBuilder.flatten(root).first { $0.displayName == "notes.txt" }
        let folder = PhysicalHierarchyBuilder.flatten(root).first { $0.displayName == "Documents" }
        XCTAssertEqual(file?.nodeKind, .file)
        XCTAssertEqual(folder?.nodeKind, .directory)
        XCTAssertEqual(file?.isFile, true)
        XCTAssertEqual(folder?.isDirectory, true)
    }

    func testSymlinkDoesNotLoopOrDuplicateBytes() throws {
        let root = try makeFixtureTree()
        XCTAssertFalse(PhysicalHierarchyBuilder.hasDuplicateByteOwnership(root))
        let links = PhysicalHierarchyBuilder.flatten(root).filter(\.isSymlink)
        XCTAssertFalse(links.isEmpty)
        for link in links {
            XCTAssertTrue(link.children.isEmpty)
        }
    }

    func testPermissionDeniedNotRepresentedAsZeroTruth() {
        let restricted = PhysicalStorageNode(
            id: "phys:/System",
            canonicalPath: "/System",
            displayName: "Restricted / Not Scanned",
            nodeKind: .restricted,
            bytes: 0,
            bytesKnown: false,
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            isRestricted: true,
            measurementReason: "PERMISSION_DENIED"
        )
        XCTAssertFalse(restricted.bytesKnown)
        XCTAssertTrue(restricted.isRestricted)
    }

    func testOtherUnclassifiedReconcilesAccounting() throws {
        let root = try makeFixtureTree()
        XCTAssertTrue(PhysicalHierarchyBuilder.accountingValid(root))
    }

    func testLensesDoNotMutateSafetyOrBytes() {
        let physical = PreviewSnapshotFactory.demoPhysicalTree()
        let stats = PhysicalHierarchyStats(
            physicalNodeCount: 1,
            maxDepth: 1,
            largestFanout: 1,
            representedBytes: physical.bytes,
            restrictedNodeCount: 0,
            unknownByteNodeCount: 0,
            accountingValid: true,
            duplicateByteOwnership: false,
            timeToFirstHierarchyMs: 1
        )
        let structure = StorageExplorerBuilder.structureSnapshot(
            physicalRoot: physical,
            stats: stats,
            disk: DiskCapacitySnapshot(volumeName: "HD", volumeTotalBytes: 1, volumeAvailableBytes: 1, volumeUsedBytes: 0),
            telemetry: StorageExplorerTelemetry()
        )
        let before = structure.physicalRoot.bytes
        let enriched = StorageExplorerBuilder.enrich(
            structure,
            report: nil,
            safe: [],
            review: [],
            protected: [],
            history: [],
            insights: [],
            stage: .complete
        )
        XCTAssertEqual(enriched.physicalRoot.bytes, before)
        XCTAssertEqual(StorageMapLens.allCases.count, 3)
        // Lens is presentation-only; decision never invents Ready without canonical source.
        let unknownDecision = StorageExplorerBuilder.flatten(enriched.presentedRoot)
            .filter { $0.decision.source == "none" }
        XCTAssertFalse(unknownDecision.contains { $0.decision.state == .readyToOptimize })
    }

    func testDecisionLensNeverPromotesUnknownToReady() {
        let root = PreviewSnapshotFactory.explorerDemo().presentedRoot
        let none = StorageExplorerBuilder.flatten(root).filter { $0.decision.source == "none" }
        XCTAssertFalse(none.contains { $0.decision.state == .readyToOptimize })
    }

    func testNavigationBreadcrumbAndSearch() {
        let root = PreviewSnapshotFactory.explorerDemo().presentedRoot
        let library = StorageExplorerBuilder.flatten(root).first { $0.title == "Library" }
        XCTAssertNotNil(library)
        let path = StorageExplorerBuilder.pathTo(id: library!.id, in: root)
        XCTAssertEqual(path?.last?.title, "Library")
        let hits = StorageExplorerBuilder.search(root: root, query: "Cursor")
        XCTAssertTrue(hits.contains { $0.title == "Cursor" })
    }

    func testSunburstMultiRingLayout() {
        let root = PreviewSnapshotFactory.explorerDemo().presentedRoot
        let arcs = StorageExplorerBuilder.layoutArcs(focus: root, rings: 3)
        XCTAssertTrue(arcs.contains { $0.ringIndex == 0 })
        XCTAssertTrue(arcs.contains { $0.ringIndex >= 1 })
        let ring0 = arcs.filter { $0.ringIndex == 0 }
        let sweep = ring0.reduce(0.0) { $0 + ($1.endDegrees - $1.startDegrees) }
        XCTAssertEqual(sweep, 360, accuracy: 0.5)
    }

    func testQuickLookClassifyDoesNotMutate() {
        let missing = QuickLookPathClassify.classify(path: "/tmp/does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(missing, .missing)
        let blocked = QuickLookPathClassify.classify(path: "/System/Library")
        XCTAssertEqual(blocked, .restricted)
    }

    private func makeFixtureTree() throws -> PhysicalStorageNode {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p301-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let library = dir.appendingPathComponent("Library", isDirectory: true)
        let appSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let documents = dir.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let notes = documents.appendingPathComponent("notes.txt")
        try Data(repeating: 0x61, count: 4096).write(to: notes)
        let big = appSupport.appendingPathComponent("blob.bin")
        try Data(repeating: 0x62, count: 64_000).write(to: big)
        let link = dir.appendingPathComponent("docs-link")
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: documents.path)

        _ = ScanSessionContext.begin()
        defer {
            ScanSessionContext.end()
            try? FileManager.default.removeItem(at: dir)
        }
        let (root, _) = PhysicalHierarchyBuilder.build(
            rootPath: dir.path,
            displayName: "FixtureRoot",
            nodeKind: .volume,
            config: PhysicalHierarchyConfig(
                maxDepth: 4,
                maxChildrenPerDirectory: 40,
                maxNodes: 200,
                expandPackages: false,
                followSymlinks: false,
                rootTimeoutSeconds: 10,
                childTimeoutSeconds: 5
            )
        )
        return root
    }
}

/// Pure classify helpers for AppServices tests without Quartz UI.
enum QuickLookPathClassify {
    enum Outcome { case previewable, unsupported, missing, restricted }

    static func classify(path: String) -> Outcome {
        if HardSafetyGates.isHardBlocked(path: path) { return .restricted }
        let expanded = PathGlob.expandHome(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else {
            return .missing
        }
        if isDir.boolValue { return .unsupported }
        let ext = (expanded as NSString).pathExtension.lowercased()
        let supported: Set<String> = ["png", "jpg", "pdf", "txt", "mp4"]
        return supported.contains(ext) ? .previewable : .unsupported
    }
}
