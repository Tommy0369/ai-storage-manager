import XCTest
@testable import SafetyCore

final class ReconstructionAndGitTests: XCTestCase {
    func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testReconstructedKBProvenance() throws {
        let url = repoRoot().appendingPathComponent("knowledge/source/storage_safety_knowledge_base_v0.1-reconstructed.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let meta = json["knowledge_base"] as! [String: Any]
        XCTAssertEqual(meta["record_count"] as? Int, 178)
        XCTAssertEqual(meta["original_source_artifact_available"] as? Bool, false)
        XCTAssertEqual(meta["canonical_status"] as? String, "PROVISIONAL")
        XCTAssertEqual(meta["not_the_deep_research_original"] as? Bool, true)
        let rules = json["rules"] as! [[String: Any]]
        XCTAssertEqual(rules.count, 178)
        XCTAssertEqual((json["knowledge_base"] as! [String: Any])["version"] as? String, "0.1-reconstructed")
    }

    func testManifestKeepsOriginalUnavailable() throws {
        let url = repoRoot().appendingPathComponent("knowledge/manifests/knowledge_base_v0.1_manifest.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let original = json["original_deep_research_kb"] as! [String: Any]
        XCTAssertEqual(original["available"] as? Bool, false)
        XCTAssertEqual(original["known_to_have_existed"] as? Bool, true)
        let current = json["current_kb"] as! [String: Any]
        XCTAssertEqual(current["type"] as? String, "RECONSTRUCTED")
    }

    func testGitDetectorFindsThisRepo() {
        let root = repoRoot().path
        let detector = GitDetector(searchRoots: [root], maxRepos: 5)
        let found = detector.detect(home: FileManager.default.homeDirectoryForCurrentUser.path, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id == "git.dot_git" })
        XCTAssertTrue(found.contains { $0.entity.id == "git.working_tree" })
    }

    func testGreenAuditorDemotesUnknownPredicate() throws {
        let url = repoRoot().appendingPathComponent("knowledge/compiled/compiled_rules_v0.1.json")
        let doc = try KnowledgeBaseLoader().load(from: url)
        let entity = StorageEntity(
            id: "xcode.derived_data",
            kind: .generatedBuild,
            category: "DEVELOPER",
            subcategory: "XCODE",
            displayName: "DerivedData",
            path: FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer/Xcode/DerivedData",
            logicalBytes: 10
        )
        let detected = DetectedEntity(entity: entity, bucket: .developer, domain: "Xcode", associatedProcesses: [], identified: true)
        var decision = SafetyDecision(
            entity: entity,
            action: .moveToTrash,
            safetyClass: .green,
            safetyScore: SafetyScore(value: 98),
            reasonCodes: ["TEST"],
            sideEffects: [],
            matchedRuleID: "xcode.derived_data",
            evaluationLayer: .exactVendor,
            evidenceConfidence: 0.2,
            userExplanationJA: "x",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        let item = ClassifiedItem(
            detected: detected,
            decision: decision,
            semantic: LLMBoundary.freeze(decision),
            allocatedBytes: 10,
            actionVariants: [:],
            inclusiveBytes: 10,
            exclusiveBytes: 10,
            resolution: .l4SemanticEntity
        )
        let evidence = EvidenceBundle(canonicalPath: entity.path, openFileHandle: .unknown, owningProcessRunning: .unknown, sourceOfTruth: .false, regenerable: .true)
        let (_, record) = GreenCandidateAuditor(knowledge: doc).audit(item: item, evidence: evidence, state: RuntimeState())
        XCTAssertTrue(record.downgradedFromGreen)
        XCTAssertNotEqual(record.safetyClass, .green)
    }
}
