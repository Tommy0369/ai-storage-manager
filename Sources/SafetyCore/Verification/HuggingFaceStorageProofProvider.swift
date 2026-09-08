import Foundation

/// Read-only Hugging Face Hub cache proof. Never mutates. Never assigns SafetyClass.
public struct HuggingFaceStorageProofProvider: VendorStorageProofProvider {
    public let vendor: VendorStorageKind = .huggingFace
    public var fileManager: FileManager
    /// Optional remote probe — defaults off. Failures must remain UNKNOWN.
    public var remoteProbe: ((String, String?) -> VendorReacquisitionState)?

    public init(
        fileManager: FileManager = .default,
        remoteProbe: ((String, String?) -> VendorReacquisitionState)? = nil
    ) {
        self.fileManager = fileManager
        self.remoteProbe = remoteProbe
    }

    public func prove(rootPath: String, budgetMs: Int) -> VendorProofInventory {
        let started = Date()
        let root = (rootPath as NSString).standardizingPath
        let hub = resolveHubRoot(root)
        var metadataReads = 0
        var notes: [String] = []
        var claimsAttempted = 0
        var claimsVerified = 0
        var claimsUnknown = 0
        var claimsConflicted = 0
        var networkCalls = 0

        var entities: [VendorSemanticEntity] = []
        var blobRefsByKey: [String: VendorBlobRef] = [:]
        var repoDirs: [String] = []

        if fileManager.fileExists(atPath: hub),
           let kids = try? fileManager.contentsOfDirectory(atPath: hub) {
            metadataReads += 1
            repoDirs = kids.filter { $0.hasPrefix("models--") || $0.hasPrefix("datasets--") || $0.hasPrefix("spaces--") }
                .map { (hub as NSString).appendingPathComponent($0) }
                .sorted()
        } else {
            notes.append("HF_HUB_MISSING")
            claimsAttempted += 1
            claimsUnknown += 1
        }

        for repoPath in repoDirs {
            if msSince(started) > budgetMs {
                notes.append("PROOF_BUDGET_EXCEEDED")
                break
            }
            let folderName = (repoPath as NSString).lastPathComponent
            let (repoID, kindPrefix) = decodeRepoFolder(folderName)
            let entityRepoID = "ai.hf.repo.\(repoID.replacingOccurrences(of: "/", with: "."))"

            let refsDir = (repoPath as NSString).appendingPathComponent("refs")
            let snapshotsDir = (repoPath as NSString).appendingPathComponent("snapshots")
            let blobsDir = (repoPath as NSString).appendingPathComponent("blobs")

            var revisions: [(name: String, commit: String)] = []
            if fileManager.fileExists(atPath: refsDir),
               let refs = try? fileManager.contentsOfDirectory(atPath: refsDir) {
                metadataReads += 1
                for ref in refs where !ref.hasPrefix(".") {
                    let refPath = (refsDir as NSString).appendingPathComponent(ref)
                    metadataReads += 1
                    if let data = fileManager.contents(atPath: refPath),
                       let commit = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !commit.isEmpty {
                        revisions.append((ref, commit))
                    }
                }
            }

            // Blob index for this repo (content-addressed filenames).
            var localBlobBytes: [String: Int64] = [:]
            var localBlobPaths: [String: String] = [:]
            if fileManager.fileExists(atPath: blobsDir),
               let names = try? fileManager.contentsOfDirectory(atPath: blobsDir) {
                metadataReads += 1
                for name in names where !name.hasPrefix(".") {
                    let path = (blobsDir as NSString).appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
                    if let attrs = try? fileManager.attributesOfItem(atPath: path),
                       let size = attrs[.size] as? NSNumber {
                        localBlobBytes[name] = size.int64Value
                        localBlobPaths[name] = path
                        metadataReads += 1
                    }
                }
            }

            // Snapshot → blob digests via symlink targets.
            var snapshotEntities: [VendorSemanticEntity] = []
            var blobToSnapshots: [String: Set<String>] = [:]
            var snapshotDirs: [String] = []
            if fileManager.fileExists(atPath: snapshotsDir),
               let snaps = try? fileManager.contentsOfDirectory(atPath: snapshotsDir) {
                metadataReads += 1
                snapshotDirs = snaps.filter { !$0.hasPrefix(".") }.sorted()
            }

            for snapName in snapshotDirs {
                let snapPath = (snapshotsDir as NSString).appendingPathComponent(snapName)
                let snapEntityID = "ai.hf.snapshot.\(repoID.replacingOccurrences(of: "/", with: ".")).\(snapName.prefix(12))"
                var digests: [String] = []
                var missing = false
                if let files = try? fileManager.contentsOfDirectory(atPath: snapPath) {
                    metadataReads += 1
                    for file in files where !file.hasPrefix(".") {
                        let full = (snapPath as NSString).appendingPathComponent(file)
                        metadataReads += 1
                        if let dest = try? fileManager.destinationOfSymbolicLink(atPath: full) {
                            let blobName = (dest as NSString).lastPathComponent
                            digests.append(blobName)
                            blobToSnapshots[blobName, default: []].insert(snapEntityID)
                            if localBlobBytes[blobName] == nil {
                                // Resolve relative path size if needed.
                                let resolved = (snapPath as NSString).appendingPathComponent(dest)
                                if let attrs = try? fileManager.attributesOfItem(atPath: resolved),
                                   let size = attrs[.size] as? NSNumber {
                                    localBlobBytes[blobName] = size.int64Value
                                    localBlobPaths[blobName] = resolved
                                } else {
                                    missing = true
                                }
                            }
                        } else {
                            // Non-symlink file — unknown integrity / noncanonical.
                            missing = true
                            notes.append("NONCANONICAL_SNAPSHOT_FILE:\(file)")
                        }
                    }
                }
                digests = Array(Set(digests)).sorted()
                claimsAttempted += 3
                let graphComplete = !digests.isEmpty && !missing
                if graphComplete { claimsVerified += 1 } else { claimsUnknown += 1 }

                var logical: Int64 = 0
                for d in digests { logical += localBlobBytes[d] ?? 0 }

                let matchedRef = revisions.first { $0.commit == snapName || $0.commit.hasPrefix(snapName) }?.name
                claimsAttempted += 1
                if matchedRef != nil || revisions.contains(where: { $0.commit == snapName }) {
                    claimsVerified += 1
                } else {
                    claimsUnknown += 1
                }

                snapshotEntities.append(VendorSemanticEntity(
                    vendor: .huggingFace,
                    entityKind: .snapshot,
                    entityID: snapEntityID,
                    displayIdentity: "\(repoID)@\(String(snapName.prefix(12)))",
                    canonicalPath: snapPath,
                    logicalBytes: logical,
                    uniqueBytes: nil, // filled after reverse index
                    sharedBytes: nil,
                    originIdentity: repoID,
                    revisionIdentity: snapName,
                    referenceScope: graphComplete ? .exclusive : .incomplete,
                    referenceGraphComplete: graphComplete,
                    runtimeState: .unknown,
                    runtimeConfidence: .unknown,
                    reacquisition: .remoteAvailabilityUnknown,
                    reacquisitionConfidence: .unknown,
                    provenanceConfidence: kindPrefix == "models" ? .verified : .inferred,
                    isUserOriginalSuspect: false,
                    referencedBlobDigests: digests,
                    topBlockers: [
                        graphComplete ? nil : "REFERENCE_GRAPH_INCOMPLETE",
                        "REACQUISITION_REMOTE_UNKNOWN",
                        "VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE"
                    ].compactMap { $0 },
                    preferredActionHint: .vendorNativeCleanup,
                    notes: matchedRef.map { ["REF:\($0)"] } ?? ["REVISION_REF_UNMATCHED"]
                ))
            }

            // Fill unique/shared per snapshot using reverse refs (within repo).
            for i in snapshotEntities.indices {
                var unique: Int64 = 0
                var shared: Int64 = 0
                var sharedFound = false
                let graphOK = snapshotEntities[i].referenceGraphComplete
                for d in snapshotEntities[i].referencedBlobDigests {
                    let size = localBlobBytes[d] ?? 0
                    let refs = blobToSnapshots[d] ?? []
                    if refs.count > 1 {
                        shared += size
                        sharedFound = true
                    } else {
                        unique += size
                    }
                    let key = "\(repoID)::\(d)"
                    blobRefsByKey[key] = VendorBlobRef(
                        digest: d,
                        path: localBlobPaths[d],
                        bytes: size,
                        present: localBlobBytes[d] != nil,
                        referencingEntityIDs: Array(refs).sorted(),
                        scope: refs.count > 1 ? .shared : (refs.isEmpty ? .orphanIncomplete : .exclusive)
                    )
                }
                if graphOK {
                    snapshotEntities[i].uniqueBytes = unique
                    snapshotEntities[i].sharedBytes = shared
                    snapshotEntities[i].referenceScope = sharedFound ? .shared : .exclusive
                    claimsVerified += 1
                } else {
                    claimsUnknown += 1
                }
            }

            // Repo-level entity: unique bytes = sum of distinct blob bytes (no double count).
            let distinctBlobBytes = localBlobBytes.values.reduce(0, +)
            claimsAttempted += 4
            claimsVerified += 2 // identity + ownership of hub layout
            claimsUnknown += 1 // remote reacquisition

            var reacq: VendorReacquisitionState = .remoteAvailabilityUnknown
            var reacqConf: EvidenceConfidence = .unknown
            if let probe = remoteProbe {
                networkCalls += 1
                claimsAttempted += 1
                reacq = probe(repoID, revisions.first?.commit)
                switch reacq {
                case .unknown, .remoteAvailabilityUnknown, .authOrGatedUnknown:
                    claimsUnknown += 1
                    reacqConf = .unknown
                case .remoteUnavailable:
                    // Evidence failure / unavailable → UNKNOWN for strict reacquisition TRUE, not FALSE promotion.
                    claimsUnknown += 1
                    reacqConf = .unknown
                    notes.append("REMOTE_PROBE_UNAVAILABLE:\(repoID)")
                case .originIdentityVerified:
                    claimsVerified += 1
                    reacqConf = .verified
                case .notApplicable:
                    claimsUnknown += 1
                }
            }

            var blockers = [
                "ROOT_OR_REPO_NOT_RAW_DELETE",
                "REACQUISITION_REMOTE_UNKNOWN",
                "VENDOR_NATIVE_CLEANUP_PREFERRED"
            ]
            if snapshotEntities.contains(where: { !$0.referenceGraphComplete }) {
                blockers.append("SOME_SNAPSHOTS_INCOMPLETE")
            }

            let repoUnique = blobRefsByKey
                .filter { $0.key.hasPrefix("\(repoID)::") && $0.value.scope == .exclusive }
                .compactMap { $0.value.bytes }
                .reduce(0, +)
            let repoShared = blobRefsByKey
                .filter { $0.key.hasPrefix("\(repoID)::") && $0.value.scope == .shared }
                .compactMap { $0.value.bytes }
                .reduce(0, +)

            entities.append(VendorSemanticEntity(
                vendor: .huggingFace,
                entityKind: .repository,
                entityID: entityRepoID,
                displayIdentity: repoID,
                canonicalPath: repoPath,
                logicalBytes: distinctBlobBytes,
                uniqueBytes: repoUnique,
                sharedBytes: repoShared,
                originIdentity: repoID,
                revisionIdentity: revisions.first?.commit,
                referenceScope: repoShared > 0 ? .shared : (snapshotEntities.isEmpty ? .incomplete : .exclusive),
                referenceGraphComplete: !snapshotEntities.isEmpty && snapshotEntities.allSatisfy(\.referenceGraphComplete),
                runtimeState: .unknown,
                runtimeConfidence: .unknown,
                reacquisition: reacq,
                reacquisitionConfidence: reacqConf,
                provenanceConfidence: .verified,
                isUserOriginalSuspect: false,
                referencedBlobDigests: Array(localBlobBytes.keys).sorted(),
                topBlockers: blockers,
                preferredActionHint: .vendorNativeCleanup,
                notes: [
                    "HF_HUB_CACHE",
                    "LOGICAL_BYTES_ARE_DISTINCT_BLOBS",
                    revisions.isEmpty ? "NO_REFS" : "REFS_PRESENT"
                ]
            ))
            entities.append(contentsOf: snapshotEntities)
        }

        // Unrecognized local files under hub (not models-- etc.)
        if fileManager.fileExists(atPath: hub),
           let kids = try? fileManager.contentsOfDirectory(atPath: hub) {
            for name in kids where !name.hasPrefix(".")
                && !name.hasPrefix("models--")
                && !name.hasPrefix("datasets--")
                && !name.hasPrefix("spaces--")
                && name != "CACHEDIR.TAG" {
                let path = (hub as NSString).appendingPathComponent(name)
                entities.append(VendorSemanticEntity(
                    vendor: .huggingFace,
                    entityKind: .unknownLocal,
                    entityID: "ai.hf.unknown.\(name)",
                    displayIdentity: name,
                    canonicalPath: path,
                    logicalBytes: 0,
                    uniqueBytes: nil,
                    sharedBytes: nil,
                    originIdentity: nil,
                    revisionIdentity: nil,
                    referenceScope: .incomplete,
                    referenceGraphComplete: false,
                    runtimeState: .unknown,
                    runtimeConfidence: .unknown,
                    reacquisition: .unknown,
                    reacquisitionConfidence: .unknown,
                    provenanceConfidence: .unknown,
                    isUserOriginalSuspect: true,
                    referencedBlobDigests: [],
                    topBlockers: ["UNRECOGNIZED_LOCAL_FILE", "USER_ORIGINAL_PROTECTION"],
                    preferredActionHint: .keep,
                    notes: ["Never promote because path is under huggingface"]
                ))
                claimsAttempted += 1
                claimsUnknown += 1
            }
        }

        let totalDistinct = blobRefsByKey.values.compactMap(\.bytes).reduce(0, +)
        entities.insert(VendorSemanticEntity(
            vendor: .huggingFace,
            entityKind: .hubRoot,
            entityID: "ai.hf.hub",
            displayIdentity: "Hugging Face Hub Cache",
            canonicalPath: hub,
            logicalBytes: totalDistinct,
            uniqueBytes: blobRefsByKey.values.filter { $0.scope == .exclusive }.compactMap(\.bytes).reduce(0, +),
            sharedBytes: blobRefsByKey.values.filter { $0.scope == .shared }.compactMap(\.bytes).reduce(0, +),
            originIdentity: "huggingface",
            revisionIdentity: nil,
            referenceScope: .shared,
            referenceGraphComplete: entities.contains { $0.entityKind == .repository && $0.referenceGraphComplete },
            runtimeState: .unknown,
            runtimeConfidence: .unknown,
            reacquisition: .remoteAvailabilityUnknown,
            reacquisitionConfidence: .unknown,
            provenanceConfidence: .verified,
            isUserOriginalSuspect: false,
            referencedBlobDigests: [],
            topBlockers: [
                "ROOT_SCOPE_NOT_AUTO_CLEANABLE",
                "REACQUISITION_REMOTE_UNKNOWN",
                "VENDOR_NATIVE_CLEANUP_PREFERRED"
            ],
            preferredActionHint: .vendorNativeCleanup,
            notes: ["Do not treat entire HF home as disposable cache"]
        ), at: 0)

        let inventory = VendorProofInventory(
            vendor: .huggingFace,
            rootPath: hub,
            entities: entities,
            blobs: Array(blobRefsByKey.values).sorted { $0.digest < $1.digest },
            claimsAttempted: claimsAttempted,
            claimsVerified: claimsVerified,
            claimsUnknown: claimsUnknown,
            claimsConflicted: claimsConflicted,
            metadataReads: metadataReads,
            vendorCLICalls: 0,
            networkCalls: networkCalls,
            proofRuntimeMs: msSince(started),
            secondCrawlerAdded: false,
            notes: notes
        )
        VendorStorageProofIndex.store(inventory)
        return inventory
    }

    private func resolveHubRoot(_ root: String) -> String {
        let lower = root.lowercased()
        if lower.hasSuffix("/hub") { return root }
        if lower.contains("/huggingface/hub") {
            if let r = lower.range(of: "/huggingface/hub") {
                let end = root.index(root.startIndex, offsetBy: root.distance(from: root.startIndex, to: r.upperBound))
                return String(root[..<end])
            }
        }
        let candidate = (root as NSString).appendingPathComponent("hub")
        if fileManager.fileExists(atPath: candidate) { return candidate }
        return root
    }

    private func decodeRepoFolder(_ name: String) -> (String, String) {
        // models--org--name → org/name
        let parts = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first else { return (name, "unknown") }
        let rest = parts.dropFirst().joined(separator: "-")
        // Folder uses `--` as separator between org segments.
        let decoded = name
            .replacingOccurrences(of: "models--", with: "")
            .replacingOccurrences(of: "datasets--", with: "")
            .replacingOccurrences(of: "spaces--", with: "")
            .replacingOccurrences(of: "--", with: "/")
        return (decoded, first.replacingOccurrences(of: "--", with: ""))
    }

    private func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
