import Foundation

public struct CursorStoresVerificationDetector: EntityDetector {
    public let domain = "AI Tools"
    public let bucket = SystemDataBucket.developer
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let storesRoot = "\(home)/Library/Application Support/Cursor/snapshots/stores"
        guard FileManager.default.fileExists(atPath: storesRoot) else { return [] }
        var out: [DetectedEntity] = []
        let index = CursorWorkspaceIdentityResolver.sharedIndex(home: home)
        let cursor = ProductIdentity(name: "Cursor", confidence: .inferred)

        for store in ChildFolderEnumerator(maxChildren: 12).immediateDirectories(at: storesRoot) {
            let marker = Self.readMarker("\(store.path)/baseline.marker")
            let identity = CursorWorkspaceIdentityResolver.resolveStore(storeID: store.name, index: index)
            var rels = identity.workspaceRelationships(storePath: store.path)
            var reasons: [String] = []
            var conf: EvidenceConfidence = identity.relationshipConfidence

            if SharedMetadataCache.pathExists("\(store.path)/baseline.marker") {
                rels.append(EntityRelationship(
                    type: .observedInCursorContext,
                    target: store.path,
                    presence: .present,
                    confidence: .inferred
                ))
            } else {
                reasons.append(UnknownReasonCode.provenanceNoManifest.rawValue)
            }

            if let reason = identity.unknownReason { reasons.append(reason) }
            if !identity.explicitMetadataReference, identity.relationshipConfidence != .verified {
                reasons.append(identity.unknownReason ?? UnknownReasonCode.cursorStoreUUIDNotReferenced.rawValue)
                if marker["root_key"] == nil {
                    reasons.append(UnknownReasonCode.cursorMetadataMissing.rawValue)
                }
            }

            let note = DetectionAnnotation(
                detectorID: "cursor.stores.verify",
                specificity: 110,
                semanticType: "CURSOR_SNAPSHOT_STORE",
                lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .inferred, activeState: .unknown),
                provenance: ProvenanceEvidence(
                    generatedByProduct: cursor,
                    relatedWorkspace: rels.first?.target,
                    relatedManifest: FileManager.default.fileExists(atPath: "\(store.path)/baseline.marker") ? "\(store.path)/baseline.marker" : nil,
                    storageRole: .generatedArtifact,
                    confidence: conf,
                    unknownReasons: reasons
                ),
                relationships: rels,
                unknownReasons: reasons
            )
            if let n = node(
                id: "cursor.snapshots.store.\(store.name)",
                kind: .generatedBuild,
                category: "AI_DEV",
                sub: "Cursor",
                path: store.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                processes: ["Cursor"],
                annotation: note
            ) { out.append(n) }

            if let n = node(
                id: "cursor.snapshots.store.\(store.name).objects",
                kind: .generatedBuild,
                category: "AI_DEV",
                sub: "Cursor",
                path: "\(store.path)/objects",
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                processes: ["Cursor"],
                annotation: DetectionAnnotation(
                    detectorID: "cursor.stores.verify",
                    specificity: 110,
                    semanticType: "CURSOR_SNAPSHOT_GENERATED",
                    lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .inferred),
                    provenance: ProvenanceEvidence(generatedByProduct: cursor, storageRole: .generatedArtifact, confidence: conf),
                    relationships: rels
                )
            ) { out.append(n) }
        }
        return out
    }

    static func readMarker(_ path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { map[parts[0]] = parts[1] }
        }
        return map
    }

    /// workspace.json contains folder URI — map by folder basename hash is unreliable;
    /// instead index by workspace folder path existence for rootrefs, and by exact store UUID if present in JSON text.
    static func loadWorkspaceJSONMap(home: String) -> [String: String] {
        let root = "\(home)/Library/Application Support/Cursor/User/workspaceStorage"
        var map: [String: String] = [:]
        let kids = ChildFolderEnumerator(maxChildren: 80).immediateDirectories(at: root)
        for kid in kids {
            let jsonPath = "\(kid.path)/workspace.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let folder = (obj["folder"] as? String) ?? ""
            let path = folder
                .replacingOccurrences(of: "file://", with: "")
                .removingPercentEncoding ?? folder
            if path.isEmpty { continue }
            // If store UUID appears in anysphere retrieval dirs, link; else map workspaceStorage id → path for REFERENCED_BY
            map[kid.name] = path
            if let text = String(data: data, encoding: .utf8) {
                for store in ChildFolderEnumerator(maxChildren: 12).immediateDirectories(at: "\(home)/Library/Application Support/Cursor/snapshots/stores") {
                    if text.contains(store.name) {
                        map[store.name] = path
                    }
                }
            }
        }
        return map
    }
}

public struct CloudResolutionDetector: EntityDetector {
    public let domain = "Cloud"
    public let bucket = SystemDataBucket.cloud
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        var out: [DetectedEntity] = []
        let providers: [(String, String, String)] = [
            ("cloud.icloud.mobile_documents", "\(home)/Library/Mobile Documents", "iCloud Drive"),
            ("cloud.fileprovider.root", "\(home)/Library/CloudStorage", "File Provider"),
        ]
        for p in providers {
            let cloudMeta = Self.observeCloudState(path: p.1)
            let identity = ProductIdentity(name: p.2, confidence: cloudMeta.providerConfidence)
            var reasons = cloudMeta.unknownReasons
            let note = DetectionAnnotation(
                detectorID: "cloud.resolve",
                specificity: 90,
                semanticType: "CLOUD_PROVIDER_ROOT",
                lifecycle: LifecycleEvidence(role: .mixed, roleConfidence: .inferred, mixedContent: true, unknownReasons: reasons),
                provenance: ProvenanceEvidence(
                    generatedByProduct: identity,
                    storageRole: .mixed,
                    confidence: cloudMeta.providerConfidence,
                    unknownReasons: reasons
                ),
                owningProducts: [identity],
                unknownReasons: reasons
            )
            if let n = node(id: p.0, kind: .cloudLocalMaterialized, category: "CLOUD", sub: p.2, path: p.1, scanner: scanner, bucket: bucket, domain: domain, annotation: note) {
                out.append(n)
            }
            _ = cloudMeta
        }
        let fp = "\(home)/Library/CloudStorage"
        for kid in ChildFolderEnumerator(maxChildren: 20).immediateDirectories(at: fp) {
            let provider = Self.providerName(from: kid.name)
            let conf: EvidenceConfidence = provider == kid.name ? .unknown : .inferred
            let cloudMeta = Self.observeCloudState(path: kid.path)
            var reasons = cloudMeta.unknownReasons
            if conf == .unknown { reasons.append(UnknownReasonCode.unknownProvider.rawValue) }
            let note = DetectionAnnotation(
                detectorID: "cloud.resolve",
                specificity: 95,
                semanticType: "CLOUD_FILE_PROVIDER_DOMAIN",
                lifecycle: LifecycleEvidence(role: .mixed, roleConfidence: .inferred, mixedContent: true),
                provenance: ProvenanceEvidence(
                    generatedByProduct: ProductIdentity(name: provider, confidence: conf),
                    storageRole: .mixed,
                    confidence: conf == .unknown ? .unknown : cloudMeta.providerConfidence,
                    unknownReasons: reasons
                ),
                unknownReasons: reasons
            )
            if let n = node(
                id: "cloud.fileprovider.\(kid.name)",
                kind: .cloudPlaceholder,
                category: "CLOUD",
                sub: provider,
                path: kid.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                annotation: note
            ) { out.append(n) }
        }
        return out
    }

    struct CloudObservation {
        var providerConfidence: EvidenceConfidence
        var remoteCopy: PredicateValue
        var syncState: PredicateValue
        var unknownReasons: [String]
    }

    /// Read-only File Provider / ubiquitous item probes. Path alone never VERIFIED remote.
    static func observeCloudState(path: String) -> CloudObservation {
        var reasons: [String] = []
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey,
        ]
        let vals = try? url.resourceValues(forKeys: keys)
        guard vals?.isUbiquitousItem == true else {
            // Non-ubiquitous CloudStorage folder still may be File Provider — remote unknown
            reasons.append(UnknownReasonCode.unknownRemoteCopy.rawValue)
            reasons.append(UnknownReasonCode.unknownSyncState.rawValue)
            return CloudObservation(providerConfidence: .inferred, remoteCopy: .unknown, syncState: .unknown, unknownReasons: reasons)
        }

        var remote: PredicateValue = .unknown
        var sync: PredicateValue = .unknown
        if let status = vals?.ubiquitousItemDownloadingStatus {
            switch status {
            case .current:
                remote = .true
                sync = .true
            case .downloaded:
                remote = .true
                sync = .unknown
                reasons.append(UnknownReasonCode.unknownSyncState.rawValue)
            case .notDownloaded:
                remote = .true // still remote-backed placeholder
                sync = .false
            default:
                reasons.append(UnknownReasonCode.unknownRemoteCopy.rawValue)
                reasons.append(UnknownReasonCode.unknownSyncState.rawValue)
            }
        } else {
            reasons.append(UnknownReasonCode.unknownRemoteCopy.rawValue)
            reasons.append(UnknownReasonCode.unknownSyncState.rawValue)
        }
        if vals?.ubiquitousItemHasUnresolvedConflicts == true {
            sync = .false
            reasons.append(UnknownReasonCode.unknownSyncState.rawValue)
        }
        let conf: EvidenceConfidence = (remote != .unknown) ? .verified : .inferred
        return CloudObservation(providerConfidence: conf, remoteCopy: remote, syncState: sync, unknownReasons: Array(Set(reasons)))
    }

    static func providerName(from folder: String) -> String {
        let lower = folder.lowercased()
        if lower.contains("dropbox") { return "Dropbox" }
        if lower.contains("onedrive") || lower.contains("microsoft") { return "OneDrive" }
        if lower.contains("google") { return "Google Drive" }
        if lower.contains("icloud") { return "iCloud" }
        return folder
    }
}

public struct VoiceMemosDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.userData
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Group Containers/group.com.apple.VoiceMemos.shared"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let identity = ProductIdentity(name: "Voice Memos", bundleIdentifier: "group.com.apple.VoiceMemos.shared", confidence: .verified)
        func note(_ semantic: String, role: LifecycleRole, conf: EvidenceConfidence = .verified) -> DetectionAnnotation {
            DetectionAnnotation(
                detectorID: "voicememos",
                specificity: 100,
                semanticType: semantic,
                lifecycle: LifecycleEvidence(role: role, roleConfidence: conf),
                provenance: ProvenanceEvidence(generatedByProduct: identity, bundleIdentifier: identity.bundleIdentifier, storageRole: role, confidence: .verified),
                owningProducts: [identity]
            )
        }
        if let n = node(id: "voicememos.root", kind: .userOriginal, category: "USER", sub: "Voice Memos", path: root, scanner: scanner, bucket: bucket, domain: domain, annotation: note("VOICE_MEMOS_ROOT", role: .mixed, conf: .inferred)) {
            out.append(n)
        }
        if let n = node(id: "voicememos.recordings", kind: .userOriginal, category: "USER", sub: "Voice Memos", path: "\(root)/Recordings", scanner: scanner, bucket: bucket, domain: domain, annotation: note("VOICE_MEMOS_RECORDINGS", role: .userContent)) {
            out.append(n)
        }
        if let n = node(id: "voicememos.library", kind: .applicationSupport, category: "USER", sub: "Voice Memos", path: "\(root)/Library", scanner: scanner, bucket: bucket, domain: domain, annotation: note("VOICE_MEMOS_LIBRARY", role: .mixed, conf: .inferred)) {
            out.append(n)
        }
        return out
    }
}
