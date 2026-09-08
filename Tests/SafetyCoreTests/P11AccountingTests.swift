import XCTest
@testable import SafetyCore

final class P11AccountingTests: XCTestCase {
    func testParentChildExclusive() {
        let parent = AccountingInput(id: "p", path: "/tmp/as", inclusiveBytes: 40, safetyClass: .red, resolution: .l1PathBucket)
        let child = AccountingInput(id: "c", path: "/tmp/as/Cursor", inclusiveBytes: 20, safetyClass: .red, resolution: .l3Product)
        let other = AccountingInput(id: "o", path: "/tmp/as/Other", inclusiveBytes: 5, safetyClass: .yellow, resolution: .l3Product)
        let r = ByteAccountant.account([parent, child, other])
        let p = r.nodes.first { $0.id == "p" }!
        let c = r.nodes.first { $0.id == "c" }!
        XCTAssertEqual(p.exclusiveBytes, 15)
        XCTAssertEqual(c.exclusiveBytes, 20)
        XCTAssertEqual(r.uniqueTotal, 40)
        XCTAssertEqual(r.duplicateBytesRemoved, 25)
        XCTAssertEqual(r.classUnique["RED"], 35)
        XCTAssertEqual(r.classUnique["YELLOW"], 5)
        XCTAssertLessThanOrEqual(r.classUnique.values.reduce(0, +), r.uniqueTotal)
    }

    func testClassUniqueCannotExceedUnique() {
        let r = ByteAccountant.account([
            AccountingInput(id: "a", path: "/a", inclusiveBytes: 100, safetyClass: .green, resolution: .l4SemanticEntity),
            AccountingInput(id: "b", path: "/a/b", inclusiveBytes: 40, safetyClass: .unknown, resolution: .l3Product),
        ])
        XCTAssertFalse(r.classificationExceedsUnique)
        XCTAssertEqual(r.uniqueTotal, 100)
    }

    func testCoverageCannotExceed100() {
        XCTAssertEqual(ByteAccountant.coverage(uniqueBytes: 200, scannedBytes: 100), 100)
        XCTAssertEqual(IdentifiedStorageCoverage(scannedBytes: 10, identifiedBytes: 10, unknownBytes: 0).percent, 100)
    }

    func testEvidenceUnknownIsNotFalse() {
        XCTAssertEqual(PredicateValue.unknown, PredicateValue.unknown)
        XCTAssertNotEqual(PredicateValue.unknown, PredicateValue.false)
        let checker = LSOFHandleChecker()
        let v = checker.hasOpenHandles(path: "/tmp/this-path-should-not-exist-\(UUID().uuidString)")
        XCTAssertNotEqual(v, PredicateValue.true)
    }

    func testApplicationSupportDecomposition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)")
        let cursor = root.appendingPathComponent("Cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: cursor.appendingPathComponent("f.txt"))
        let d = FolderDecomposer(
            domain: "macOS",
            bucket: .developer,
            parentID: "macos.application_support",
            parentPath: root.path,
            maxChildren: 10
        )
        let found = d.detect(home: "/tmp", scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.subcategory == "Cursor" })
        XCTAssertNotEqual(found.first?.entity.id, "macos.application_support")
    }

    func testDockerNotInstalledStillSafe() {
        let report = DockerProbe().probe(home: "/tmp/no-such-home-\(UUID().uuidString)")
        XCTAssertFalse(report.storageLocations.contains { $0.contains("no-such-home") && FileManager.default.fileExists(atPath: $0) })
        XCTAssertEqual(report.dockerAppExists, FileManager.default.fileExists(atPath: "/Applications/Docker.app"))
    }

    func testSemanticLevels() {
        let nodes = [
            AccountedNode(id: "p", path: "/a", inclusiveBytes: 40, exclusiveBytes: 15, safetyClass: .red, resolution: .l1PathBucket, measurementKnown: true, measurementQuality: .exact, exclusiveKnown: true),
            AccountedNode(id: "c", path: "/a/c", inclusiveBytes: 25, exclusiveBytes: 25, safetyClass: .red, resolution: .l3Product, measurementKnown: true, measurementQuality: .exact, exclusiveKnown: true),
        ]
        let cov = ByteAccountant.semanticCoverage(nodes: nodes, scannedBytes: 40)
        XCTAssertEqual(cov.l3PlusPercent, 62.5, accuracy: 0.1)
        XCTAssertEqual(cov.l5Percent, 0)
        XCTAssertLessThanOrEqual(cov.identifiedPercent, 100)
    }

    func testNestedGitExclusive() {
        let git = AccountingInput(id: "git.dot_git", path: "/repo/.git", inclusiveBytes: 100, safetyClass: .red, resolution: .l4SemanticEntity)
        let obj = AccountingInput(id: "git.objects", path: "/repo/.git/objects", inclusiveBytes: 80, safetyClass: .red, resolution: .l4SemanticEntity)
        let r = ByteAccountant.account([git, obj])
        XCTAssertEqual(r.nodes.first { $0.id == "git.dot_git" }?.exclusiveBytes, 20)
        XCTAssertEqual(r.uniqueTotal, 100)
    }
}
