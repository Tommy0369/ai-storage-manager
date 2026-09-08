import Foundation

/// Read-only Ollama model/manifest/blob proof. Never mutates. Never assigns SafetyClass.
public struct OllamaStorageProofProvider: VendorStorageProofProvider {
    public let vendor: VendorStorageKind = .ollama
    public var fileManager: FileManager
    public var processNames: [String]
    public var allowCLI: Bool

    public init(
        fileManager: FileManager = .default,
        processNames: [String] = [],
        allowCLI: Bool = false
    ) {
        self.fileManager = fileManager
        self.processNames = processNames
        self.allowCLI = allowCLI
    }

    private func resolveModelsRoot(_ root: String) -> String {
        let lower = root.lowercased()
        if lower.hasSuffix("/models") { return root }
        if let range = lower.range(of: "/.ollama/models") {
            let end = root.index(root.startIndex, offsetBy: root.distance(from: root.startIndex, to: range.upperBound))
            return String(root[..<end])
        }
        let candidate = (root as NSString).appendingPathComponent("models")
        if fileManager.fileExists(atPath: candidate) { return candidate }
        return root
    }

    public func prove(rootPath: String, budgetMs: Int) -> VendorProofInventory {
        let started = Date()
        let root = (rootPath as NSString).standardizingPath
        let modelsRoot = resolveModelsRoot(root)
        // Refuse non-model Ollama paths (e.g. logs) — avoid empty false inventories.
        let lower = modelsRoot.lowercased()
        guard lower.contains("/.ollama/models") || lower.hasSuffix("/models"),
              fileManager.fileExists(atPath: (modelsRoot as NSString).appendingPathComponent("manifests"))
                || fileManager.fileExists(atPath: (modelsRoot as NSString).appendingPathComponent("blobs"))
        else {
            let empty = VendorProofInventory(
                vendor: .ollama,
                rootPath: modelsRoot,
                entities: [],
                blobs: [],
                claimsAttempted: 0,
                claimsVerified: 0,
                claimsUnknown: 0,
                claimsConflicted: 0,
                metadataReads: 0,
                vendorCLICalls: 0,
                networkCalls: 0,
                proofRuntimeMs: msSince(started),
                secondCrawlerAdded: false,
                notes: ["NOT_OLLAMA_MODELS_ROOT"]
            )
            // Do not store empty non-root inventories into the session index.
            return empty
        }
        if let existing = VendorStorageProofIndex.inventory(forRoot: modelsRoot),
           existing.entities.contains(where: { $0.entityKind == .model || $0.entityKind == .modelsRoot }) {
            return existing
        }
        return proveModelsRoot(modelsRoot, budgetMs: budgetMs, started: started)
    }

    private func proveModelsRoot(_ modelsRoot: String, budgetMs: Int, started: Date) -> VendorProofInventory {
        var metadataReads = 0
        var notes: [String] = []
        var claimsAttempted = 0
        var claimsVerified = 0
        var claimsUnknown = 0
        var claimsConflicted = 0

        let blobsDir = (modelsRoot as NSString).appendingPathComponent("blobs")
        let manifestsDir = (modelsRoot as NSString).appendingPathComponent("manifests")

        var blobBytes: [String: Int64] = [:]
        var blobPaths: [String: String] = [:]
        if fileManager.fileExists(atPath: blobsDir) {
            if let kids = try? fileManager.contentsOfDirectory(atPath: blobsDir) {
                metadataReads += 1
                for name in kids where name.hasPrefix("sha256-") || name.hasPrefix("sha256:") {
                    let digest = normalizeDigest(name)
                    let path = (blobsDir as NSString).appendingPathComponent(name)
                    if let attrs = try? fileManager.attributesOfItem(atPath: path),
                       let size = attrs[.size] as? NSNumber {
                        blobBytes[digest] = size.int64Value
                        blobPaths[digest] = path
                        metadataReads += 1
                    }
                }
            }
        }

        struct ModelDraft {
            var entityID: String
            var display: String
            var path: String
            var digests: [String]
            var missing: [String]
            var origin: String
            var customSuspect: Bool
        }

        var drafts: [ModelDraft] = []
        var reverse: [String: Set<String>] = [:]

        if fileManager.fileExists(atPath: manifestsDir) {
            let manifests = enumerateManifestFiles(at: manifestsDir, metadataReads: &metadataReads)
            for file in manifests {
                if msSince(started) > budgetMs {
                    notes.append("PROOF_BUDGET_EXCEEDED")
                    break
                }
                metadataReads += 1
                guard let data = fileManager.contents(atPath: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    claimsAttempted += 1
                    claimsUnknown += 1
                    notes.append("MANIFEST_UNREADABLE:\(file)")
                    continue
                }
                let relative = String(file.dropFirst(manifestsDir.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let parts = relative.split(separator: "/").map(String.init)
                guard parts.count >= 2 else { continue }
                let tag = parts.last ?? "latest"
                let nameParts = Array(parts.dropLast())
                let modelName: String
                if nameParts.count >= 3 {
                    // registry/namespace/model
                    modelName = "\(nameParts[nameParts.count - 2])/\(nameParts[nameParts.count - 1])"
                } else if nameParts.count == 2 {
                    modelName = "\(nameParts[0])/\(nameParts[1])"
                } else {
                    modelName = nameParts.joined(separator: "/")
                }
                let display = "\(modelName):\(tag)"
                let origin = nameParts.count >= 3 ? nameParts.dropLast(2).joined(separator: "/") : "local"
                let entityID = "ai.ollama.model.\(display.replacingOccurrences(of: "/", with: "."))"
                let customSuspect = origin == "local"
                    || relative.lowercased().contains("modelfile")
                    || !relative.contains("registry.ollama.ai")

                var digests: [String] = []
                if let config = json["config"] as? [String: Any],
                   let digest = config["digest"] as? String {
                    digests.append(normalizeDigest(digest))
                }
                if let layers = json["layers"] as? [[String: Any]] {
                    for layer in layers {
                        if let digest = layer["digest"] as? String {
                            digests.append(normalizeDigest(digest))
                        }
                    }
                }
                digests = Array(Set(digests)).sorted()
                var missing: [String] = []
                for d in digests {
                    reverse[d, default: []].insert(entityID)
                    if blobBytes[d] == nil {
                        missing.append(d)
                    }
                }
                drafts.append(ModelDraft(
                    entityID: entityID,
                    display: display,
                    path: file,
                    digests: digests,
                    missing: missing,
                    origin: origin,
                    customSuspect: customSuspect
                ))
            }
        } else {
            notes.append("MANIFESTS_DIR_MISSING")
            claimsAttempted += 1
            claimsUnknown += 1
        }

        let serviceRunning = processNames.contains { $0.lowercased().contains("ollama") }
        // Process existence alone must not imply all models ACTIVE.
        let runtimeState: ObservedActiveState = .unknown
        let runtimeConfidence: EvidenceConfidence = serviceRunning ? .inferred : .unknown

        var entities: [VendorSemanticEntity] = []
        for draft in drafts {
            claimsAttempted += 5
            let graphComplete = draft.missing.isEmpty && !draft.digests.isEmpty
            if graphComplete { claimsVerified += 1 } else { claimsUnknown += 1 }

            var logical: Int64 = 0
            var unique: Int64 = 0
            var shared: Int64 = 0
            var scope: VendorReferenceScope = graphComplete ? .exclusive : .incomplete
            var sharedFound = false
            for d in draft.digests {
                let size = blobBytes[d] ?? 0
                logical += size
                let refs = reverse[d] ?? []
                if refs.count > 1 {
                    shared += size
                    sharedFound = true
                } else if refs.count == 1 {
                    unique += size
                }
            }
            if graphComplete {
                scope = sharedFound ? .shared : .exclusive
                claimsVerified += 1 // shared-byte status
            }

            // Ownership by path layout under .ollama/models
            claimsVerified += 1 // vendor ownership of layout
            claimsVerified += 1 // entity identity from manifest path
            // Origin identity known locally; remote availability unknown without network.
            claimsVerified += 1 // origin identity string
            claimsUnknown += 1 // reacquisition / remote
            if draft.customSuspect {
                claimsUnknown += 1
            }

            var blockers: [String] = []
            if !graphComplete { blockers.append("REFERENCE_GRAPH_INCOMPLETE") }
            blockers.append("REACQUISITION_REMOTE_UNKNOWN")
            blockers.append("VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE")
            if draft.customSuspect {
                blockers.append("USER_ORIGINAL_OR_CUSTOM_MODEL_SUSPECT")
            }
            if sharedFound {
                blockers.append("SHARED_BLOBS_PRESENT")
            }

            entities.append(VendorSemanticEntity(
                vendor: .ollama,
                entityKind: .model,
                entityID: draft.entityID,
                displayIdentity: draft.display,
                canonicalPath: draft.path,
                logicalBytes: logical,
                uniqueBytes: graphComplete ? unique : nil,
                sharedBytes: graphComplete ? shared : nil,
                originIdentity: draft.origin,
                revisionIdentity: draft.display,
                referenceScope: scope,
                referenceGraphComplete: graphComplete,
                runtimeState: runtimeState,
                runtimeConfidence: runtimeConfidence,
                reacquisition: .remoteAvailabilityUnknown,
                reacquisitionConfidence: .unknown,
                provenanceConfidence: draft.customSuspect ? .unknown : .verified,
                isUserOriginalSuspect: draft.customSuspect,
                referencedBlobDigests: draft.digests,
                topBlockers: blockers,
                preferredActionHint: draft.customSuspect ? .keep : .vendorNativeCleanup,
                notes: [
                    "MODEL_LEVEL_ENTITY",
                    serviceRunning ? "OLLAMA_SERVICE_PROCESS_OBSERVED" : "OLLAMA_SERVICE_PROCESS_UNKNOWN",
                    "MODEL_ACTIVITY_NOT_PROVEN_FROM_SERVICE_ALONE"
                ]
            ))
        }

        // Orphan-looking blobs: present on disk but not referenced in any parsed manifest.
        let referenced = Set(reverse.keys)
        var blobRefs: [VendorBlobRef] = []
        for (digest, bytes) in blobBytes {
            let refs = Array(reverse[digest] ?? []).sorted()
            let scope: VendorReferenceScope
            if refs.isEmpty {
                scope = .orphanIncomplete
                claimsAttempted += 1
                claimsUnknown += 1
                notes.append("ORPHAN_BLOB_INCOMPLETE_GRAPH:\(digest.prefix(16))")
            } else if refs.count == 1 {
                scope = .exclusive
            } else {
                scope = .shared
            }
            blobRefs.append(VendorBlobRef(
                digest: digest,
                path: blobPaths[digest],
                bytes: bytes,
                present: true,
                referencingEntityIDs: refs,
                scope: scope
            ))
            _ = referenced
        }

        // Root aggregate for folder-level entity proof.
        let rootUnique = blobRefs.filter { $0.scope == .exclusive }.compactMap(\.bytes).reduce(0, +)
        let rootShared = blobRefs.filter { $0.scope == .shared }.compactMap(\.bytes).reduce(0, +)
        entities.insert(VendorSemanticEntity(
            vendor: .ollama,
            entityKind: .modelsRoot,
            entityID: "ai.ollama.models",
            displayIdentity: "Ollama Models",
            canonicalPath: modelsRoot,
            logicalBytes: blobBytes.values.reduce(0, +),
            uniqueBytes: rootUnique,
            sharedBytes: rootShared,
            originIdentity: "ollama",
            revisionIdentity: nil,
            referenceScope: drafts.isEmpty ? .incomplete : (rootShared > 0 ? .shared : .exclusive),
            referenceGraphComplete: !drafts.isEmpty && drafts.allSatisfy(\.missing.isEmpty),
            runtimeState: runtimeState,
            runtimeConfidence: runtimeConfidence,
            reacquisition: .remoteAvailabilityUnknown,
            reacquisitionConfidence: .unknown,
            provenanceConfidence: .verified,
            isUserOriginalSuspect: false,
            referencedBlobDigests: blobRefs.map(\.digest),
            topBlockers: [
                "ROOT_SCOPE_NOT_AUTO_CLEANABLE",
                "REACQUISITION_REMOTE_UNKNOWN",
                "VENDOR_NATIVE_CLEANUP_PREFERRED"
            ],
            preferredActionHint: .vendorNativeCleanup,
            notes: ["Prefer model-level entities over raw blob cleanup"]
        ), at: 0)

        var cliCalls = 0
        if allowCLI {
            // Intentionally unused in default path — no per-entity CLI, no mutation.
            notes.append("CLI_DISABLED_BY_DEFAULT")
        }

        let inventory = VendorProofInventory(
            vendor: .ollama,
            rootPath: modelsRoot,
            entities: entities,
            blobs: blobRefs,
            claimsAttempted: claimsAttempted,
            claimsVerified: claimsVerified,
            claimsUnknown: claimsUnknown,
            claimsConflicted: claimsConflicted,
            metadataReads: metadataReads,
            vendorCLICalls: cliCalls,
            networkCalls: 0,
            proofRuntimeMs: msSince(started),
            secondCrawlerAdded: false,
            notes: notes
        )
        VendorStorageProofIndex.store(inventory)
        return inventory
    }

    private func enumerateManifestFiles(at manifestsDir: String, metadataReads: inout Int) -> [String] {
        var out: [String] = []
        guard let enumerator = fileManager.enumerator(atPath: manifestsDir) else { return out }
        metadataReads += 1
        while let rel = enumerator.nextObject() as? String {
            let full = (manifestsDir as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            // Skip hidden junk; manifests are leaf files without extension typically.
            if rel.contains(".DS_Store") { continue }
            out.append(full)
        }
        return out
    }

    private func normalizeDigest(_ raw: String) -> String {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.hasPrefix("sha256:") {
            d = "sha256-" + d.dropFirst("sha256:".count)
        }
        if !d.hasPrefix("sha256-"), d.count == 64 {
            d = "sha256-" + d
        }
        return d
    }

    private func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
