import XCTest
@testable import AppServices
import SafetyCore

/// P3.0.1 regression: UNKNOWN root measurement must not collapse into numeric zero.
final class P301PhysicalMapAccountingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.setOverride(.english)
    }

    override func tearDown() {
        L10n.setOverride(.english)
        super.tearDown()
    }

    func testRootMeasuredExactReconciles() {
        let leaf = known("A", bytes: 40_000_000_000, depth: 1)
        let root = PhysicalStorageNode(
            id: "phys:/root",
            canonicalPath: "/root",
            displayName: "Root",
            nodeKind: .volume,
            bytes: 100_000_000_000,
            bytesKnown: true,
            exclusiveBytes: 60_000_000_000,
            exclusiveKnown: true,
            children: [leaf],
            depth: 0,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .exact
        )
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertEqual(accounting.basis, .rootMeasured)
        XCTAssertEqual(accounting.mappedBytes, 100_000_000_000)
        XCTAssertTrue(accounting.rootTotalKnown)
        XCTAssertFalse(accounting.fallbackUsed)
        XCTAssertTrue(accounting.accountingValid)
    }

    func testRootTimeoutUsesKnownChildrenLowerBound() {
        let a = known("A", bytes: 20_000_000_000, depth: 1)
        let b = known("B", bytes: 30_000_000_000, depth: 1)
        let root = unknownRoot(children: [a, b], reason: "DU_TIMEOUT")
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertEqual(accounting.basis, .knownChildrenLowerBound)
        XCTAssertEqual(accounting.mappedBytes, 50_000_000_000)
        XCTAssertEqual(accounting.coverage, .partial)
        XCTAssertEqual(accounting.rootMeasurementStatus, .timeout)
        XCTAssertNil(accounting.rootMeasuredBytes)
        XCTAssertFalse(accounting.rootTotalKnown)
        XCTAssertTrue(accounting.fallbackUsed)
        XCTAssertTrue(accounting.accountingValid)
        XCTAssertFalse(accounting.unknownRemainderKnown)
    }

    func testRootTimeoutCenterIsPositiveMappedNotZero() {
        let child = known("Library", bytes: 25_000_000_000, depth: 1)
        let root = unknownRoot(children: [child], reason: "DU_TIMEOUT")
        let snap = snapshot(for: root)
        XCTAssertEqual(snap.physicalMapBytes, 25_000_000_000)
        XCTAssertNotEqual(snap.physicalMapBytes, 0)
        XCTAssertEqual(snap.mapAccounting?.basis, .knownChildrenLowerBound)
        let label = MapCenterLabel.make(focus: snap.presentedRoot, accounting: snap.mapAccounting!)
        XCTAssertEqual(label.primary, UICandidateMapper.byteLabel(25_000_000_000))
        XCTAssertFalse(label.showsNumericZero)
        XCTAssertEqual(label.footnote, "mapped")
    }

    func testRootTimeoutWithNoKnownChildrenDoesNotShowZeroGB() {
        let unknownChild = PhysicalStorageNode(
            id: "phys:/root/x",
            canonicalPath: "/root/x",
            displayName: "X",
            nodeKind: .directory,
            bytes: 0,
            bytesKnown: false,
            children: [],
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementReason: "DU_TIMEOUT"
        )
        let root = unknownRoot(children: [unknownChild], reason: "DU_TIMEOUT")
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertEqual(accounting.basis, .noMeasurement)
        XCTAssertNil(accounting.mappedBytes)
        let label = MapCenterLabel.make(
            focus: present(root),
            accounting: accounting
        )
        XCTAssertFalse(label.showsNumericZero)
        XCTAssertEqual(label.primary, "—")
        XCTAssertEqual(label.footnote, "Mapping unavailable")
    }

    func testUnknownChildExcludedFromMappedLowerBound() {
        let knownA = known("A", bytes: 10_000_000_000, depth: 1)
        let knownB = known("B", bytes: 20_000_000_000, depth: 1)
        let unknown = PhysicalStorageNode(
            id: "phys:/root/u",
            canonicalPath: "/root/u",
            displayName: "U",
            nodeKind: .directory,
            bytes: 0,
            bytesKnown: false,
            children: [],
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementReason: "DU_TIMEOUT"
        )
        let root = unknownRoot(children: [knownA, knownB, unknown], reason: "DU_TIMEOUT")
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertEqual(accounting.mappedBytes, 30_000_000_000)
        XCTAssertEqual(accounting.coverage, .partial)
        XCTAssertFalse(accounting.unknownRemainderKnown)
    }

    func testNoParentDescendantDoubleCounting() {
        let grand = known("Grand", path: "/root/Child/Grand", bytes: 20_000_000_000, depth: 2)
        let child = PhysicalStorageNode(
            id: "phys:/root/Child",
            canonicalPath: "/root/Child",
            displayName: "Child",
            nodeKind: .directory,
            bytes: 20_000_000_000,
            bytesKnown: true,
            exclusiveBytes: 0,
            exclusiveKnown: true,
            children: [grand],
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .exact
        )
        let root = unknownRoot(children: [child], reason: "DU_TIMEOUT")
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertEqual(accounting.mappedBytes, 20_000_000_000)
        XCTAssertNotEqual(accounting.mappedBytes, 40_000_000_000)
    }

    func testSuccessfulRootMeasurementWinsOverFallback() {
        let child = known("A", bytes: 50_000_000_000, depth: 1)
        let root = PhysicalStorageNode(
            id: "phys:/root",
            canonicalPath: "/root",
            displayName: "Root",
            nodeKind: .volume,
            bytes: 60_000_000_000,
            bytesKnown: true,
            exclusiveBytes: 10_000_000_000,
            exclusiveKnown: true,
            children: [child],
            depth: 0,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .exact
        )
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertEqual(accounting.basis, .rootMeasured)
        XCTAssertEqual(accounting.mappedBytes, 60_000_000_000)
        XCTAssertFalse(accounting.fallbackUsed)
    }

    func testAccountingValidDoesNotRequireCoverageComplete() {
        let child = known("A", bytes: 12_000_000_000, depth: 1)
        let root = unknownRoot(children: [child], reason: "DU_TIMEOUT")
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        XCTAssertTrue(accounting.accountingValid)
        XCTAssertEqual(accounting.coverage, .partial)
    }

    func testReportSerializationPreservesFallbackSemantics() {
        let child = known("A", bytes: 18_000_000_000, depth: 1)
        let root = unknownRoot(children: [child], reason: "DU_TIMEOUT")
        let snap = snapshot(for: root)
        let report = StorageExplorerBuilder.report(from: snap, falseGREEN: 0, duplicateEvaluations: 0)
        XCTAssertGreaterThan(report.physicalMapBytes, 0)
        XCTAssertEqual(report.physicalMapAccountingBasis, "KNOWN_CHILDREN_LOWER_BOUND")
        XCTAssertEqual(report.physicalMapCoverage, "PARTIAL")
        XCTAssertEqual(report.rootMeasurementStatus, "TIMEOUT")
        XCTAssertEqual(report.rootTotalKnown, false)
        XCTAssertEqual(report.fallbackUsed, true)
        XCTAssertEqual(report.knownChildMappedBytes, 18_000_000_000)
        XCTAssertTrue(report.accountingValid)
        XCTAssertEqual(report.unknownRemainderKnown, false)
        XCTAssertNil(report.rootMeasuredBytes)
    }

    func testCenterLabelNeverUsesDiskUsedFallback() {
        let child = known("A", bytes: 8_000_000_000, depth: 1)
        let root = unknownRoot(children: [child], reason: "DU_TIMEOUT")
        let snap = snapshot(for: root)
        let label = MapCenterLabel.make(focus: snap.presentedRoot, accounting: snap.mapAccounting!)
        XCTAssertEqual(label.primary, UICandidateMapper.byteLabel(8_000_000_000))
        XCTAssertNotEqual(label.primary, UICandidateMapper.byteLabel(347_000_000_000))
        XCTAssertEqual(snap.physicalMapBytes, 8_000_000_000)
        XCTAssertNotEqual(snap.physicalMapBytes, snap.diskCapacity.volumeUsedBytes)
    }

    /// Permanent deep-hierarchy fixture: TIMEOUT root must never become 0 mapped.
    func testDeterministicDeepTimeoutHierarchyNeverCollapsesToZero() {
        let deepLeaf = known("Models", path: "/root/Library/AI/Models", bytes: 8_100_000_000, depth: 3)
        let ai = PhysicalStorageNode(
            id: "phys:/root/Library/AI",
            canonicalPath: "/root/Library/AI",
            displayName: "AI",
            nodeKind: .directory,
            bytes: 8_100_000_000,
            bytesKnown: true,
            exclusiveBytes: 0,
            exclusiveKnown: true,
            children: [deepLeaf],
            depth: 2,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .exact
        )
        let library = PhysicalStorageNode(
            id: "phys:/root/Library",
            canonicalPath: "/root/Library",
            displayName: "Library",
            nodeKind: .directory,
            bytes: 27_400_000_000,
            bytesKnown: true,
            exclusiveBytes: 19_300_000_000,
            exclusiveKnown: true,
            children: [ai],
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .exact
        )
        let downloads = known("Downloads", bytes: 4_200_000_000, depth: 1)
        let xcode = known("Xcode", path: "/root/Xcode", bytes: 2_700_000_000, depth: 1)
        let timedOutSibling = PhysicalStorageNode(
            id: "phys:/root/Huge",
            canonicalPath: "/root/Huge",
            displayName: "Huge",
            nodeKind: .directory,
            bytes: 0,
            bytesKnown: false,
            children: [],
            depth: 1,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .unknown,
            measurementReason: "DU_TIMEOUT"
        )
        let root = unknownRoot(children: [library, downloads, xcode, timedOutSibling], reason: "DU_TIMEOUT")
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        let snap = snapshot(for: root)
        let label = MapCenterLabel.make(focus: snap.presentedRoot, accounting: accounting)

        XCTAssertEqual(accounting.rootMeasurementStatus, .timeout)
        XCTAssertEqual(accounting.basis, .knownChildrenLowerBound)
        XCTAssertEqual(accounting.coverage, .partial)
        XCTAssertEqual(accounting.mappedBytes, 34_300_000_000)
        XCTAssertGreaterThan(accounting.knownChildMappedBytes, 0)
        XCTAssertTrue(accounting.accountingValid)
        XCTAssertFalse(accounting.rootTotalKnown)
        XCTAssertFalse(accounting.unknownRemainderKnown)
        XCTAssertTrue(accounting.fallbackUsed)
        XCTAssertEqual(snap.physicalMapBytes, 34_300_000_000)
        XCTAssertNotEqual(snap.physicalMapBytes, 0)
        XCTAssertNotEqual(snap.physicalMapBytes, snap.diskCapacity.volumeUsedBytes)
        XCTAssertFalse(label.showsNumericZero)
        XCTAssertNotEqual(label.primary, "0 GB")
        XCTAssertFalse(label.primary.hasPrefix("0 "))
        XCTAssertEqual(label.footnote, "mapped")
    }

    // MARK: - Helpers

    private func known(
        _ name: String,
        path: String? = nil,
        bytes: Int64,
        depth: Int
    ) -> PhysicalStorageNode {
        let p = path ?? "/root/\(name)"
        return PhysicalStorageNode(
            id: "phys:" + p,
            canonicalPath: p,
            displayName: name,
            nodeKind: .directory,
            bytes: bytes,
            bytesKnown: true,
            exclusiveBytes: bytes,
            exclusiveKnown: true,
            children: [],
            depth: depth,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .exact
        )
    }

    private func unknownRoot(children: [PhysicalStorageNode], reason: String) -> PhysicalStorageNode {
        PhysicalStorageNode(
            id: "phys:/root",
            canonicalPath: "/root",
            displayName: "Macintosh HD",
            nodeKind: .volume,
            bytes: 0,
            bytesKnown: false,
            exclusiveBytes: 0,
            exclusiveKnown: false,
            children: children,
            depth: 0,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: .unknown,
            measurementReason: reason
        )
    }

    private func snapshot(for root: PhysicalStorageNode) -> StorageExplorerSnapshot {
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        let stats = PhysicalHierarchyStats(
            physicalNodeCount: PhysicalHierarchyBuilder.flatten(root).count,
            maxDepth: 2,
            largestFanout: root.children.count,
            representedBytes: accounting.reportMappedBytes,
            restrictedNodeCount: 0,
            unknownByteNodeCount: 1,
            accountingValid: accounting.accountingValid,
            duplicateByteOwnership: false,
            timeToFirstHierarchyMs: 1
        )
        return StorageExplorerBuilder.structureSnapshot(
            physicalRoot: root,
            stats: stats,
            disk: DiskCapacitySnapshot(
                volumeName: "Macintosh HD",
                volumeTotalBytes: 494_000_000_000,
                volumeAvailableBytes: 140_000_000_000,
                volumeUsedBytes: 347_000_000_000
            ),
            telemetry: StorageExplorerTelemetry(physicalNodeCount: stats.physicalNodeCount, maxDepth: 2)
        )
    }

    private func present(_ root: PhysicalStorageNode) -> StorageNodePresentation {
        snapshot(for: root).presentedRoot
    }
}
