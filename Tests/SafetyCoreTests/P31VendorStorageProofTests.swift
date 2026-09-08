import XCTest
@testable import SafetyCore

final class P31VendorStorageProofTests: XCTestCase {
    private var tempRoot: URL!
    private lazy var engine = SafetyRuleEngine(knowledge: KnowledgeBaseDocument(version: "t", principle: "t", rules: []))

    override func setUp() {
        super.setUp()
        VendorStorageProofIndex.reset()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("p31-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        VendorStorageProofIndex.reset()
        super.tearDown()
    }

    func testOllamaExclusiveBlobs() throws {
        let models = tempRoot.appendingPathComponent("ollama/models")
        try writeOllamaFixture(
            models: models,
            modelsSpec: [
                ("registry.ollama.ai/library/alpha/latest", ["sha256-aaa111", "sha256-bbb222"], [100, 200])
            ]
        )
        let inv = OllamaStorageProofProvider().prove(rootPath: models.path, budgetMs: 2_000)
        let model = try XCTUnwrap(inv.entities.first { $0.entityKind == .model })
        XCTAssertTrue(model.referenceGraphComplete)
        XCTAssertEqual(model.logicalBytes, 300)
        XCTAssertEqual(model.uniqueBytes, 300)
        XCTAssertEqual(model.sharedBytes, 0)
        XCTAssertEqual(model.referenceScope, .exclusive)
        XCTAssertNotEqual(model.preferredActionHint, .moveToTrash)
    }

    func testOllamaSharedBlobNotDoubleCountedAndNotTrash() throws {
        let models = tempRoot.appendingPathComponent("ollama-shared/models")
        try writeOllamaFixture(
            models: models,
            modelsSpec: [
                ("registry.ollama.ai/library/one/latest", ["sha256-shared1", "sha256-only1"], [1_000, 100]),
                ("registry.ollama.ai/library/two/latest", ["sha256-shared1", "sha256-only2"], [1_000, 200])
            ]
        )
        let inv = OllamaStorageProofProvider().prove(rootPath: models.path, budgetMs: 2_000)
        let modelsOnly = inv.entities.filter { $0.entityKind == .model }
        XCTAssertEqual(modelsOnly.count, 2)
        let sharedBlob = try XCTUnwrap(inv.blobs.first { $0.digest.contains("shared1") })
        XCTAssertEqual(sharedBlob.scope, .shared)
        XCTAssertEqual(sharedBlob.referencingEntityIDs.count, 2)

        let logicalSum = modelsOnly.reduce(Int64(0)) { $0 + $1.logicalBytes }
        XCTAssertEqual(logicalSum, 2_300)
        let uniqueSum = modelsOnly.compactMap(\.uniqueBytes).reduce(0, +)
        XCTAssertEqual(uniqueSum, 300)
        let root = try XCTUnwrap(inv.entities.first { $0.entityKind == .modelsRoot })
        XCTAssertEqual(root.logicalBytes, 1_300)

        for model in modelsOnly {
            var item = classified(id: model.entityID, path: model.canonicalPath, bytes: model.logicalBytes)
            item.verification = VerificationAnnotation(
                uniqueBytesProven: model.uniqueBytes,
                sharedBytesProven: model.sharedBytes,
                referenceGraphConfidence: .verified
            )
            let trash = ActionSafetyEvaluator.evaluate(
                item: item,
                action: .moveToTrash,
                engine: engine,
                evidence: EvidenceBundle(canonicalPath: model.canonicalPath),
                state: RuntimeState()
            )
            XCTAssertFalse(trash.eligible)
            XCTAssertTrue(trash.blockedReasons.contains(.applicationManagedData))
        }
    }

    func testOllamaMissingBlobKeepsIncompleteGraph() throws {
        let models = tempRoot.appendingPathComponent("ollama-missing/models")
        let manifests = models.appendingPathComponent("manifests/registry.ollama.ai/library/gap")
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)
        let manifest = """
        {"schemaVersion":2,"config":{"digest":"sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef","size":1},"layers":[]}
        """
        try manifest.write(to: manifests.appendingPathComponent("latest"), atomically: true, encoding: .utf8)
        let inv = OllamaStorageProofProvider().prove(rootPath: models.path, budgetMs: 2_000)
        let model = try XCTUnwrap(inv.entities.first { $0.entityKind == .model })
        XCTAssertFalse(model.referenceGraphComplete)
        XCTAssertEqual(model.referenceScope, .incomplete)
        XCTAssertNil(model.uniqueBytes)
    }

    func testOllamaOrphanBlobNotAutoSafe() throws {
        let models = tempRoot.appendingPathComponent("ollama-orphan/models")
        try writeOllamaFixture(
            models: models,
            modelsSpec: [
                ("registry.ollama.ai/library/keep/latest", ["sha256-keepblob"], [50])
            ]
        )
        let orphan = models.appendingPathComponent("blobs/sha256-orphanblob")
        try Data(repeating: 9, count: 77).write(to: orphan)
        let inv = OllamaStorageProofProvider().prove(rootPath: models.path, budgetMs: 2_000)
        let orphanRef = try XCTUnwrap(inv.blobs.first { $0.digest.contains("orphan") })
        XCTAssertEqual(orphanRef.scope, .orphanIncomplete)
        XCTAssertTrue(inv.notes.contains { $0.contains("ORPHAN_BLOB") })
    }

    func testOllamaServiceProcessDoesNotMarkAllModelsActive() throws {
        let models = tempRoot.appendingPathComponent("ollama-runtime/models")
        try writeOllamaFixture(
            models: models,
            modelsSpec: [("registry.ollama.ai/library/r/latest", ["sha256-r1"], [10])]
        )
        let inv = OllamaStorageProofProvider(processNames: ["ollama"]).prove(rootPath: models.path, budgetMs: 2_000)
        let model = try XCTUnwrap(inv.entities.first { $0.entityKind == .model })
        XCTAssertEqual(model.runtimeState, .unknown)
        XCTAssertNotEqual(model.runtimeConfidence, .verified)
        XCTAssertTrue(model.notes.contains("MODEL_ACTIVITY_NOT_PROVEN_FROM_SERVICE_ALONE"))
    }

    func testOllamaCustomLocalProtected() throws {
        let models = tempRoot.appendingPathComponent("ollama-custom/models")
        try writeOllamaFixture(
            models: models,
            modelsSpec: [("local/custom/mymodel/latest", ["sha256-custom1"], [42])]
        )
        let inv = OllamaStorageProofProvider().prove(rootPath: models.path, budgetMs: 2_000)
        let model = try XCTUnwrap(inv.entities.first { $0.entityKind == .model })
        XCTAssertTrue(model.isUserOriginalSuspect)
        XCTAssertEqual(model.preferredActionHint, .keep)
        XCTAssertTrue(model.topBlockers.contains("USER_ORIGINAL_OR_CUSTOM_MODEL_SUSPECT"))
    }

    func testHFSingleRepoRevision() throws {
        let hub = tempRoot.appendingPathComponent("hf/hub")
        try writeHFRepo(
            hub: hub,
            folder: "models--org--alpha",
            commit: "abc123",
            files: [("config.json", "blobA", 10), ("weights.bin", "blobB", 90)]
        )
        let inv = HuggingFaceStorageProofProvider().prove(rootPath: hub.path, budgetMs: 2_000)
        let repo = try XCTUnwrap(inv.entities.first { $0.entityKind == .repository })
        XCTAssertEqual(repo.displayIdentity, "org/alpha")
        XCTAssertEqual(repo.logicalBytes, 100)
        XCTAssertTrue(repo.referenceGraphComplete)
        let snap = try XCTUnwrap(inv.entities.first { $0.entityKind == .snapshot })
        XCTAssertEqual(snap.logicalBytes, 100)
        XCTAssertEqual(snap.uniqueBytes, 100)
    }

    func testHFSharedBlobAcrossRevisionsNotDoubleCounted() throws {
        let hub = tempRoot.appendingPathComponent("hf-shared/hub")
        let repo = hub.appendingPathComponent("models--org--shared")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 500).write(to: repo.appendingPathComponent("blobs/sharedBlob"))
        try Data(repeating: 2, count: 50).write(to: repo.appendingPathComponent("blobs/onlyA"))
        try Data(repeating: 3, count: 70).write(to: repo.appendingPathComponent("blobs/onlyB"))
        try "commitA".write(to: repo.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        try "commitB".write(to: repo.appendingPathComponent("refs/dev"), atomically: true, encoding: .utf8)
        try linkSnapshot(repo: repo, commit: "commitA", links: [("a.bin", "sharedBlob"), ("b.bin", "onlyA")])
        try linkSnapshot(repo: repo, commit: "commitB", links: [("a.bin", "sharedBlob"), ("c.bin", "onlyB")])

        let inv = HuggingFaceStorageProofProvider().prove(rootPath: hub.path, budgetMs: 2_000)
        let repository = try XCTUnwrap(inv.entities.first { $0.entityKind == .repository })
        XCTAssertEqual(repository.logicalBytes, 620)
        let snaps = inv.entities.filter { $0.entityKind == .snapshot }
        XCTAssertEqual(snaps.count, 2)
        let logicalSum = snaps.reduce(Int64(0)) { $0 + $1.logicalBytes }
        XCTAssertEqual(logicalSum, 1_120)
        XCTAssertEqual(repository.sharedBytes, 500)
        let shared = try XCTUnwrap(inv.blobs.first { $0.digest == "sharedBlob" })
        XCTAssertEqual(shared.scope, .shared)
    }

    func testHFRemoteFailureRemainsUnknown() throws {
        let hub = tempRoot.appendingPathComponent("hf-remote/hub")
        try writeHFRepo(
            hub: hub,
            folder: "models--org--gated",
            commit: "c1",
            files: [("f.bin", "b1", 8)]
        )
        let inv = HuggingFaceStorageProofProvider(remoteProbe: { _, _ in .remoteUnavailable })
            .prove(rootPath: hub.path, budgetMs: 2_000)
        let repo = try XCTUnwrap(inv.entities.first { $0.entityKind == .repository })
        XCTAssertEqual(repo.reacquisitionConfidence, .unknown)
        XCTAssertNotEqual(repo.reacquisition, .originIdentityVerified)
    }

    func testHFUnrecognizedLocalProtected() throws {
        let hub = tempRoot.appendingPathComponent("hf-unk/hub")
        try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: hub.appendingPathComponent("mysterious.bin"))
        let inv = HuggingFaceStorageProofProvider().prove(rootPath: hub.path, budgetMs: 1_000)
        let unk = try XCTUnwrap(inv.entities.first { $0.entityKind == .unknownLocal })
        XCTAssertTrue(unk.isUserOriginalSuspect)
        XCTAssertEqual(unk.preferredActionHint, .keep)
    }

    func testHFRootNeverAutoCleanable() throws {
        let hub = tempRoot.appendingPathComponent("hf-root/hub")
        try writeHFRepo(hub: hub, folder: "models--a--b", commit: "z", files: [("f", "b", 1)])
        let inv = HuggingFaceStorageProofProvider().prove(rootPath: hub.path, budgetMs: 1_000)
        let root = try XCTUnwrap(inv.entities.first { $0.entityKind == .hubRoot })
        XCTAssertTrue(root.topBlockers.contains("ROOT_SCOPE_NOT_AUTO_CLEANABLE"))
        let item = classified(id: "ai.hf.hub", path: hub.path, bytes: root.logicalBytes)
        let trash = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .moveToTrash,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: hub.path),
            state: RuntimeState()
        )
        XCTAssertFalse(trash.eligible)
    }

    func testVendorNativeCleanupNotEligibleWithoutReacquisition() throws {
        var item = classified(id: "ai.ollama.model.demo", path: "/tmp/.ollama/models/manifests/x", bytes: 1_000)
        item.verification = VerificationAnnotation(
            uniqueBytesProven: 400,
            referenceGraphConfidence: .verified,
            reacquisition: ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .filesystemMetadata,
                reasonCode: "REMOTE_UNKNOWN"
            )
        )
        let vendor = ActionSafetyEvaluator.evaluate(
            item: item,
            action: .vendorNativeCleanup,
            engine: engine,
            evidence: EvidenceBundle(canonicalPath: item.detected.entity.path),
            state: RuntimeState()
        )
        XCTAssertFalse(vendor.eligible)
        XCTAssertTrue(vendor.explanationCodes.contains("VENDOR_NATIVE_CLEANUP_PREFERRED"))
        XCTAssertTrue(vendor.explanationCodes.contains("REACQUIRABILITY_REQUIRED_REGENERABILITY_NOT_REQUIRED")
            || vendor.explanationCodes.contains("REACQUISITION_NOT_VERIFIED")
            || vendor.blockedReasons.contains(.reacquisitionNotStrictVerified))
    }

    func testNoProofNoPromotion() throws {
        let item = classified(id: "ai.hf.repo.mystery", path: "/tmp/.cache/huggingface/hub/models--x--y", bytes: 99)
        let rec = ActionRecommendationEngine.recommend(
            items: [item],
            engine: engine
        ).first
        XCTAssertEqual(rec?.recommendedAction, .keep)
        if case .verifyMore = rec?.disposition {
            // expected
        } else {
            XCTFail("expected verifyMore disposition")
        }
    }

    func testMeasurementMetricLayersConsistent() throws {
        let session = ScanSessionContext.begin()
        defer { ScanSessionContext.end() }
        session.testMeasurementOverride = { _ in
            SizeMeasurement.exact(bytes: 10, method: "test")
        }
        _ = session.measure(path: "/tmp/a", caller: "t1")
        _ = session.measure(path: "/tmp/a", caller: "t2")
        _ = session.measure(path: "/tmp/b", caller: "t3")
        XCTAssertEqual(session.measurementRequests, 3)
        XCTAssertEqual(session.measurementCacheHits + session.measurementCacheMisses, 3)
        XCTAssertEqual(session.measurementCacheHits, 1)
        XCTAssertEqual(session.measurementCacheMisses, 2)
    }

    // MARK: - helpers

    private func classified(id: String, path: String, bytes: Int64) -> ClassifiedItem {
        let entity = StorageEntity(
            id: id,
            kind: .cache,
            category: "AI_DEV",
            subcategory: id,
            displayName: id,
            path: path,
            logicalBytes: bytes
        )
        let detected = DetectedEntity(
            entity: entity,
            bucket: .developer,
            domain: "AI Tools",
            associatedProcesses: ["ollama"],
            identified: true,
            annotation: nil
        )
        let decision = SafetyDecision(
            entity: entity,
            action: .noAction,
            safetyClass: .unknown,
            safetyScore: nil,
            reasonCodes: [],
            sideEffects: [],
            matchedRuleID: nil,
            evaluationLayer: .unknownFallback,
            evidenceConfidence: 0,
            userExplanationJA: "test",
            growthCauses: [],
            requiresUserApproval: true,
            blockedBy: nil
        )
        return ClassifiedItem(
            detected: detected,
            decision: decision,
            semantic: SemanticResult(from: decision),
            allocatedBytes: bytes,
            actionVariants: [:],
            inclusiveBytes: bytes,
            exclusiveBytes: bytes,
            resolution: .l3Product,
            unknownReason: nil,
            verification: nil
        )
    }

    private func writeOllamaFixture(
        models: URL,
        modelsSpec: [(String, [String], [Int])]
    ) throws {
        let blobs = models.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        var written = Set<String>()
        for (rel, digests, sizes) in modelsSpec {
            let dir = models.appendingPathComponent("manifests").appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
            for (i, d) in digests.enumerated() {
                if !written.contains(d) {
                    try Data(repeating: UInt8((i % 200) + 1), count: sizes[i]).write(to: blobs.appendingPathComponent(d))
                    written.insert(d)
                }
            }
            let payload: [String: Any] = [
                "schemaVersion": 2,
                "config": [
                    "digest": digests[0].replacingOccurrences(of: "sha256-", with: "sha256:"),
                    "size": sizes[0]
                ],
                "layers": digests.dropFirst().enumerated().map { idx, d in
                    [
                        "digest": d.replacingOccurrences(of: "sha256-", with: "sha256:"),
                        "size": sizes[idx + 1],
                        "mediaType": "application/vnd.ollama.image.model"
                    ] as [String: Any]
                }
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            try data.write(to: dir)
        }
    }

    private func writeHFRepo(hub: URL, folder: String, commit: String, files: [(String, String, Int)]) throws {
        let repo = hub.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try commit.write(to: repo.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        var links: [(String, String)] = []
        for (name, blob, size) in files {
            try Data(repeating: 7, count: size).write(to: repo.appendingPathComponent("blobs/\(blob)"))
            links.append((name, blob))
        }
        try linkSnapshot(repo: repo, commit: commit, links: links)
    }

    private func linkSnapshot(repo: URL, commit: String, links: [(String, String)]) throws {
        let snap = repo.appendingPathComponent("snapshots/\(commit)")
        try FileManager.default.createDirectory(at: snap, withIntermediateDirectories: true)
        for (name, blob) in links {
            let link = snap.appendingPathComponent(name)
            let dest = "../../blobs/\(blob)"
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: dest)
        }
    }
}
