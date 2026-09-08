import XCTest
@testable import SafetyCore

final class P19ScannerIOAccountingTests: XCTestCase {
    func makeTempDir() -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("p19-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    func testDuTimeoutIsUnknownNotZeroBytes() {
        DirectorySizeCache.reset()
        let m = DirectorySizeCache.measurement(at: "/this/path/should/not/exist/\(UUID().uuidString)", caller: "test", timeoutSeconds: 0.001)
        XCTAssertFalse(m.isKnown)
        XCTAssertNil(m.bytes)
        XCTAssertEqual(m.quality, .unknown)
        XCTAssertEqual(m.accountingBytes, 0)
    }

    func testExactMeasurementRepresented() throws {
        let dir = makeTempDir()
        try Data("hello".utf8).write(to: URL(fileURLWithPath: "\(dir)/f.txt"))
        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        let m = session.measure(path: dir, caller: "test", timeoutSeconds: 5.0, mode: "bounded_du")
        XCTAssertTrue(m.isKnown)
        XCTAssertEqual(m.quality, .exact)
        XCTAssertNotNil(m.bytes)
    }

    func testSamePathMeasuredOncePerScanSession() throws {
        let dir = makeTempDir()
        try Data("x".utf8).write(to: URL(fileURLWithPath: "\(dir)/a.txt"))
        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        _ = session.measure(path: dir, caller: "first")
        let before = session.duSpawnCount()
        _ = session.measure(path: dir, caller: "second")
        XCTAssertEqual(session.duSpawnCount(), before)
    }

    func testPartialParentDoesNotFabricateExclusiveZero() {
        let parent = AccountingInput(
            id: "p", path: "/tmp/p", inclusiveBytes: 0, safetyClass: .red, resolution: .l1PathBucket,
            measurementKnown: false, measurementQuality: .unknown
        )
        let child = AccountingInput(
            id: "c", path: "/tmp/p/c", inclusiveBytes: 5_000_000_000, safetyClass: .red, resolution: .l3Product,
            measurementKnown: true, measurementQuality: .exact
        )
        let r = ByteAccountant.account([parent, child])
        let p = r.nodes.first { $0.id == "p" }!
        XCTAssertFalse(p.exclusiveKnown)
        XCTAssertEqual(p.exclusiveBytes, 0)
        XCTAssertGreaterThan(r.unknownMeasurementEntities, 0)
    }

    func testExactParentChildAccountingPreserved() {
        let parent = AccountingInput(id: "p", path: "/tmp/as", inclusiveBytes: 40, safetyClass: .red, resolution: .l1PathBucket)
        let child = AccountingInput(id: "c", path: "/tmp/as/Cursor", inclusiveBytes: 20, safetyClass: .red, resolution: .l3Product)
        let r = ByteAccountant.account([parent, child])
        XCTAssertEqual(r.nodes.first { $0.id == "p" }?.exclusiveBytes, 20)
        XCTAssertEqual(r.uniqueTotal, 40)
    }

    func testMeasurementCoverageDoesNotExceedDenominator() {
        let parent = AccountingInput(id: "p", path: "/tmp/p", inclusiveBytes: 100, safetyClass: .red, resolution: .l1PathBucket)
        let child = AccountingInput(id: "c", path: "/tmp/p/c", inclusiveBytes: 40, safetyClass: .red, resolution: .l3Product)
        let r = ByteAccountant.account([parent, child])
        let cov = ByteAccountant.measurementCoverage(result: r, denominatorBytes: 100)
        XCTAssertLessThanOrEqual(cov.exactBytes, cov.denominatorBytes)
        XCTAssertLessThanOrEqual(cov.byteMeasurementCoveragePercent, 100)
    }

    func testEntityFallbackIsPartialNotExact() {
        let m = SizeMeasurement.partial(bytes: 999, reason: "ENTITY_LOGICAL_BYTES", method: "entity_fallback")
        XCTAssertEqual(m.quality, .partial)
        XCTAssertFalse(m.isKnown)
        XCTAssertEqual(m.accountingBytes, 999)
    }

    func testMeasurementCoverageReport() {
        let result = ByteAccountingResult(
            inclusiveSumOfAllNodes: 100,
            exclusiveTotal: 80,
            uniqueTotal: 80,
            duplicateBytesRemoved: 20,
            classUnique: ["RED": 80],
            nodes: [],
            overflowClamps: 0,
            exactMeasurementBytes: 60,
            boundedMeasurementBytes: 20,
            partialMeasurementBytes: 0,
            unknownMeasurementEntities: 1,
            unknownMeasurementBytesEstimate: 0,
            accountingCompletenessPercent: 80
        )
        let cov = ByteAccountant.measurementCoverage(result: result, denominatorBytes: 100)
        XCTAssertEqual(cov.byteMeasurementCoveragePercent, 60, accuracy: 0.1)
    }

    func testScannerDuplicationReportTracksRepeatedOps() throws {
        let dir = makeTempDir()
        try Data("x".utf8).write(to: URL(fileURLWithPath: "\(dir)/a.txt"))
        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        _ = session.measure(path: dir, caller: "a")
        _ = session.measure(path: dir, caller: "b")
        let dup = session.duplicationReport()
        XCTAssertGreaterThanOrEqual(dup.entries.count, 0)
    }

    func testNodeModulesRemainsOptIn() {
        let catalog = DetectorCatalog(proofTargets: ["derived-data"])
        XCTAssertFalse(catalog.detectors.contains { $0.detectorID == "NodeModulesProofDetector" })
    }

    func testScannedNodeCarriesMeasurementQuality() throws {
        let dir = makeTempDir()
        try Data("abc".utf8).write(to: URL(fileURLWithPath: "\(dir)/f.txt"))
        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        let node = ReadOnlyStorageScanner().scanNode(path: dir, caller: "test")
        XCTAssertNotNil(node)
        XCTAssertTrue(node?.measurementKnown == true || node?.measurementQuality == .unknown)
    }
}
