import XCTest
@testable import SafetyCore

final class P12DeepDecompositionTests: XCTestCase {
    func knowledge() throws -> KnowledgeBaseDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SafetyCore/Resources/knowledge/compiled_rules_v0.1.json")
        return try KnowledgeBaseLoader().load(from: url)
    }

    func touch(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: path))
    }

    func testAIToolProductDecomposition() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ai-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Caches/Cursor", withIntermediateDirectories: true)
        try Data("c".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/Caches/Cursor/a"))
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/logs", withIntermediateDirectories: true)
        try Data("l".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/logs/a"))
        try FileManager.default.createDirectory(atPath: "\(home)/.ollama/models/blobs", withIntermediateDirectories: true)
        try Data("m".utf8).write(to: URL(fileURLWithPath: "\(home)/.ollama/models/blobs/b"))
        let found = AIToolDeepDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id == "ai.cursor.cache" })
        XCTAssertTrue(found.contains { $0.entity.id == "ai.cursor.logs" })
        XCTAssertTrue(found.contains { $0.entity.id == "ai.ollama.blobs" })
        XCTAssertTrue(found.contains { $0.domain == "AI Tools" })
    }

    func testCursorSemanticEntityClassification() {
        let level = ResolutionLevel.assign(entityID: "ai.cursor.cache", path: "/tmp/Cursor/Cache", predicatesAllTrue: false, safetyClass: .yellow)
        XCTAssertEqual(level, .l4SemanticEntity)
        XCTAssertGreaterThanOrEqual(level, .l4SemanticEntity)
    }

    func testClaudeCodeProtectedConfig() throws {
        let engine = SafetyRuleEngine(knowledge: try knowledge())
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/settings.json"
        let entity = StorageEntity(id: "ai.claude.settings", kind: .applicationSupport, category: "AI", subcategory: "CLAUDE", displayName: "s", path: path, logicalBytes: 1)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .userReview, evidence: EvidenceBundle(canonicalPath: path), state: RuntimeState()))
        XCTAssertEqual(d.safetyClass, .red)
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testOllamaModelStaysYellow() throws {
        let engine = SafetyRuleEngine(knowledge: try knowledge())
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.ollama/models/blobs/sha256-abc"
        let entity = StorageEntity(id: "ai.ollama.models", kind: .cache, category: "AI", subcategory: "OLLAMA", displayName: "m", path: path, logicalBytes: 9_000_000_000)
        let ev = EvidenceBundle(canonicalPath: path, openFileHandle: .false, owningProcessRunning: .false, sourceOfTruth: .false, regenerable: .true)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: ev, state: RuntimeState()))
        XCTAssertEqual(d.safetyClass, .yellow)
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testHFUnreferencedCacheCandidateNotAutoGreen() throws {
        let engine = SafetyRuleEngine(knowledge: try knowledge())
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/.cache/huggingface/hub/models--x"
        let entity = StorageEntity(id: "ai.hf.hub", kind: .cache, category: "AI", subcategory: "HF", displayName: "h", path: path, logicalBytes: 1)
        let ev = EvidenceBundle(canonicalPath: path, openFileHandle: .unknown, owningProcessRunning: .unknown, sourceOfTruth: .unknown, regenerable: .unknown)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: ev, state: RuntimeState()))
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testContainerCachesVsDocuments() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ct-\(UUID().uuidString)").path
        let bid = "com.tinyspeck.slackmacgap"
        let base = "\(home)/Library/Containers/\(bid)/Data"
        try FileManager.default.createDirectory(atPath: "\(base)/Documents", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/Library/Caches", withIntermediateDirectories: true)
        try Data("d".utf8).write(to: URL(fileURLWithPath: "\(base)/Documents/a.txt"))
        try Data("c".utf8).write(to: URL(fileURLWithPath: "\(base)/Library/Caches/a.bin"))
        let found = ContainerDeepDetector(maxContainers: 20).detect(home: home, scanner: ReadOnlyStorageScanner())
        let docs = found.first { $0.entity.id.contains(".documents") }
        let caches = found.first { $0.entity.id.contains(".caches") }
        XCTAssertEqual(docs?.entity.kind, .userOriginal)
        XCTAssertEqual(caches?.entity.kind, .cache)
        XCTAssertNotEqual(docs?.entity.kind, caches?.entity.kind)
    }

    func testContainerPreferencesProtected() throws {
        let engine = SafetyRuleEngine(knowledge: try knowledge())
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Containers/com.example.app/Data/Library/Preferences"
        let entity = StorageEntity(id: "container.com.example.app.preferences", kind: .applicationSupport, category: "C", subcategory: "prefs", displayName: "p", path: path, logicalBytes: 1)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: EvidenceBundle(canonicalPath: path), state: RuntimeState()))
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testApplicationSupportMixedSemantics() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("as-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/logs", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(home)/Library/Application Support/Cursor/User", withIntermediateDirectories: true)
        try Data("l".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/logs/a"))
        try Data("u".utf8).write(to: URL(fileURLWithPath: "\(home)/Library/Application Support/Cursor/User/s.json"))
        let found = AppSupportDeepDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        let logs = found.first { $0.entity.id.contains(".logs") }
        let user = found.first { $0.entity.id.contains(".user_settings") }
        XCTAssertEqual(logs?.entity.kind, .log)
        XCTAssertEqual(user?.entity.kind, .applicationSupport)
        XCTAssertNotEqual(logs?.entity.kind, user?.entity.kind)
    }

    func testSemanticCoverageL4Calculation() {
        let nodes = [
            AccountedNode(id: "a", path: "/a", inclusiveBytes: 100, exclusiveBytes: 40, safetyClass: .red, resolution: .l2Domain, measurementKnown: true, measurementQuality: .exact, exclusiveKnown: true),
            AccountedNode(id: "b", path: "/a/b", inclusiveBytes: 60, exclusiveBytes: 60, safetyClass: .yellow, resolution: .l4SemanticEntity, measurementKnown: true, measurementQuality: .exact, exclusiveKnown: true),
        ]
        let cov = ByteAccountant.semanticCoverage(nodes: nodes, scannedBytes: 100)
        XCTAssertEqual(cov.l4PlusPercent, 60, accuracy: 0.1)
        XCTAssertEqual(cov.l3PlusPercent, 60, accuracy: 0.1)
    }

    func stubDecision(_ entity: StorageEntity, cls: SafetyClass = .unknown, rule: String? = nil) -> SafetyDecision {
        SafetyDecision(
            entity: entity,
            action: .userReview,
            safetyClass: cls,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: rule,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0.2,
            userExplanationJA: "x",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
    }

    func classified(_ detected: DetectedEntity, level: ResolutionLevel, bytes: Int64, cls: SafetyClass = .unknown, rule: String? = nil) -> ClassifiedItem {
        let d = stubDecision(detected.entity, cls: cls, rule: rule)
        return ClassifiedItem(
            detected: detected,
            decision: d,
            semantic: LLMBoundary.freeze(d),
            allocatedBytes: bytes,
            actionVariants: [:],
            inclusiveBytes: bytes,
            exclusiveBytes: bytes,
            resolution: level
        )
    }

    func testDomainSemanticCoverage() {
        let cursor = DetectedEntity(
            entity: StorageEntity(id: "ai.cursor.cache", kind: .cache, category: "AI", subcategory: "Cursor", displayName: "c", path: "/c", logicalBytes: 10),
            bucket: .developer, domain: "AI Tools", associatedProcesses: [], identified: true
        )
        let mac = DetectedEntity(
            entity: StorageEntity(id: "macos.logs", kind: .log, category: "M", subcategory: "logs", displayName: "l", path: "/l", logicalBytes: 10),
            bucket: .generated, domain: "macOS", associatedProcesses: [], identified: true
        )
        let cov = SemanticReports.domainCoverage(items: [
            classified(cursor, level: .l4SemanticEntity, bytes: 10, cls: .yellow),
            classified(mac, level: .l1PathBucket, bytes: 10, cls: .red),
        ])
        XCTAssertEqual(cov.first { $0.domain == "AI Tools" }?.l4PlusPercent, 100)
        XCTAssertEqual(cov.first { $0.domain == "macOS" }?.l4PlusPercent, 0)
    }

    func testLargestUnresolvedBucketRanking() {
        let make: (String, Int64, ResolutionLevel, String) -> ClassifiedItem = { id, bytes, level, domain in
            let e = DetectedEntity(
                entity: StorageEntity(id: id, kind: .unknown, category: "x", subcategory: id, displayName: id, path: "/\(id)", logicalBytes: bytes),
                bucket: .developer, domain: domain, associatedProcesses: [], identified: true
            )
            return self.classified(e, level: level, bytes: bytes)
        }
        let ranked = SemanticReports.largestUnresolved(items: [
            make("small", 10, .l2Domain, "macOS"),
            make("big", 99, .l3Product, "AI Tools"),
            make("done", 1000, .l4SemanticEntity, "AI Tools"),
        ])
        XCTAssertEqual(ranked.first?.path, "/big")
        XCTAssertFalse(ranked.contains { $0.path == "/done" })
    }

    func testUnknownReasonCodes() {
        let entity = StorageEntity(id: "x", kind: .cache, category: "t", subcategory: "t", displayName: "x", path: "/x", logicalBytes: 1)
        let d = stubDecision(entity)
        let ev = EvidenceBundle(canonicalPath: "/x", openFileHandle: .unknown, owningProcessRunning: .unknown)
        XCTAssertEqual(UnknownReasonCode.classify(decision: d, evidence: ev, entity: entity), .unknownActiveState)
        let ev2 = EvidenceBundle(canonicalPath: "/x", openFileHandle: .false, owningProcessRunning: .false, regenerable: .unknown)
        XCTAssertEqual(UnknownReasonCode.classify(decision: d, evidence: ev2, entity: entity), .unknownRegenerability)
    }

    func testEvidenceUnknownReasonPreservation() {
        let snap = OpenFileSnapshot(openPaths: [], snapshotFailed: true, failureReason: "lsof permission denied")
        XCTAssertEqual(snap.hasOpenHandles(path: "/tmp"), .unknown)
        XCTAssertNotEqual(snap.hasOpenHandles(path: "/tmp"), .false)
        XCTAssertEqual(snap.failureReason, "lsof permission denied")
    }

    func testEvidenceSnapshotReuse() {
        let snap = OpenFileSnapshot(openPaths: ["/tmp/open-a"], snapshotFailed: false, failureReason: nil)
        XCTAssertEqual(snap.hasOpenHandles(path: "/tmp/open-a"), .true)
        XCTAssertEqual(snap.hasOpenHandles(path: "/tmp/open-b"), .false)
        XCTAssertEqual(snap.hasOpenHandles(path: "/tmp"), .true)
        let proc = ProcessTableSnapshot(names: ["Cursor"], snapshotFailed: false, failureReason: nil)
        XCTAssertEqual(proc.isRunning(executableNames: ["Cursor"]), .true)
        XCTAssertEqual(proc.isRunning(executableNames: ["NotHere"]), .false)
    }

    func testGreenBlockedByUnknownActiveState() throws {
        let engine = SafetyRuleEngine(knowledge: try knowledge())
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer/Xcode/DerivedData/App-abc"
        let entity = StorageEntity(id: "xcode.derived_data", kind: .generatedBuild, category: "X", subcategory: "DD", displayName: "d", path: path, logicalBytes: 1)
        let ev = EvidenceBundle(canonicalPath: path, openFileHandle: .unknown, owningProcessRunning: .false, sourceOfTruth: .false, regenerable: .true)
        let d = engine.evaluate(EvaluationRequest(entity: entity, intendedAction: .moveToTrash, evidence: ev, state: RuntimeState()))
        XCTAssertNotEqual(d.safetyClass, .green)
    }

    func testGreenBlockedByUnknownRegenerability() throws {
        let auditor = GreenCandidateAuditor(knowledge: try knowledge())
        let path = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer/Xcode/DerivedData/App-abc"
        let detected = DetectedEntity(
            entity: StorageEntity(id: "xcode.derived_data", kind: .generatedBuild, category: "X", subcategory: "DD", displayName: "d", path: path, logicalBytes: 1),
            bucket: .developer, domain: "Xcode", associatedProcesses: [], identified: true
        )
        let item = classified(detected, level: .l4SemanticEntity, bytes: 1, cls: .green, rule: "xcode.derived_data")
        var green = item.decision
        green.safetyClass = .green
        green.matchedRuleID = "xcode.derived_data"
        green.action = .moveToTrash
        let patched = ClassifiedItem(
            detected: detected,
            decision: green,
            semantic: LLMBoundary.freeze(green),
            allocatedBytes: 1,
            actionVariants: [:],
            inclusiveBytes: 1,
            exclusiveBytes: 1,
            resolution: .l4SemanticEntity
        )
        let ev = EvidenceBundle(canonicalPath: path, isSymlink: .false, openFileHandle: .false, owningProcessRunning: .false, sourceOfTruth: .false, regenerable: .unknown)
        let audited = auditor.audit(item: patched, evidence: ev, state: RuntimeState())
        XCTAssertNotEqual(audited.0.safetyClass, .green)
    }

    func testNoDoubleCountingAfterDeepDecomposition() {
        let r = ByteAccountant.account([
            AccountingInput(id: "ai.cursor_app_support", path: "/AS/Cursor", inclusiveBytes: 100, safetyClass: .red, resolution: .l3Product),
            AccountingInput(id: "ai.cursor.cache", path: "/AS/Cursor/CachedData", inclusiveBytes: 40, safetyClass: .yellow, resolution: .l4SemanticEntity),
            AccountingInput(id: "ai.cursor.logs", path: "/AS/Cursor/logs", inclusiveBytes: 10, safetyClass: .yellow, resolution: .l4SemanticEntity),
        ])
        XCTAssertEqual(r.uniqueTotal, 100)
        XCTAssertFalse(r.classificationExceedsUnique)
        XCTAssertEqual(r.nodes.first { $0.id == "ai.cursor_app_support" }?.exclusiveBytes, 50)
    }

    func testDockerFixtureWithoutRealInstall() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("dk-\(UUID().uuidString)").path
        for p in [
            "\(home)/Library/Containers/com.docker.docker/Data/vms",
            "\(home)/.docker/images",
            "\(home)/.docker/containers",
            "\(home)/.docker/volumes",
            "\(home)/.docker/buildx",
        ] {
            try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
            try Data("d".utf8).write(to: URL(fileURLWithPath: p + "/f"))
        }
        let found = DockerDetector().detect(home: home, scanner: ReadOnlyStorageScanner())
        XCTAssertTrue(found.contains { $0.entity.id == "docker.images" })
        XCTAssertTrue(found.contains { $0.entity.id == "docker.volumes_dir" })
        XCTAssertTrue(found.contains { $0.entity.id == "docker.build_cache" })
        let probe = DockerProbe().probe(home: "/tmp/no-docker-home-\(UUID().uuidString)")
        XCTAssertEqual(probe.dockerAppExists, FileManager.default.fileExists(atPath: "/Applications/Docker.app"))
    }
}
