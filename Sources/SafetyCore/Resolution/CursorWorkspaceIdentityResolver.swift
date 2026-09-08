import Foundation

public struct CursorWorkspaceIdentity: Sendable, Equatable {
    public var workspaceID: String?
    public var rootKey: String?
    public var canonicalWorkspacePath: String?
    public var relationshipConfidence: EvidenceConfidence
    public var evidenceSource: EvidenceSourceKind
    public var unknownReason: String?
    public var explicitMetadataReference: Bool
    public var workspaceExists: Bool?
    public var proofSteps: [String]

    public init(
        workspaceID: String? = nil,
        rootKey: String? = nil,
        canonicalWorkspacePath: String? = nil,
        relationshipConfidence: EvidenceConfidence = .unknown,
        evidenceSource: EvidenceSourceKind = .unknown,
        unknownReason: String? = nil,
        explicitMetadataReference: Bool = false,
        workspaceExists: Bool? = nil,
        proofSteps: [String] = []
    ) {
        self.workspaceID = workspaceID
        self.rootKey = rootKey
        self.canonicalWorkspacePath = canonicalWorkspacePath
        self.relationshipConfidence = relationshipConfidence
        self.evidenceSource = evidenceSource
        self.unknownReason = unknownReason
        self.explicitMetadataReference = explicitMetadataReference
        self.workspaceExists = workspaceExists
        self.proofSteps = proofSteps
    }

    public func asRelationship(type: RelationshipType = .belongsToWorkspace) -> EntityRelationship? {
        guard let path = canonicalWorkspacePath else {
            return EntityRelationship(
                type: type,
                target: rootKey ?? workspaceID ?? "unknown",
                presence: .unknown,
                confidence: relationshipConfidence
            )
        }
        let presence: RelationshipPresence
        if let workspaceExists {
            presence = workspaceExists ? .present : .missing
        } else {
            presence = .unknown
        }
        return EntityRelationship(type: type, target: path, presence: presence, confidence: relationshipConfidence)
    }

    /// Store/snapshot → Cursor store UUID (VERIFIED when store exists). Does not imply workspace membership.
    public func asStoreAssociation() -> EntityRelationship? {
        guard let key = rootKey ?? workspaceID else { return nil }
        let exists = workspaceExists ?? SharedMetadataCache.pathExists(
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Cursor/snapshots/stores/\(key)"
        )
        let conf: EvidenceConfidence = exists ? .verified : .unknown
        return EntityRelationship(
            type: .associatedWithCursorStore,
            target: key,
            presence: exists ? .present : .unknown,
            confidence: conf
        )
    }

    /// Honest workspace edges: VERIFIED/INFERRED belongsToWorkspace plus explicit UNKNOWN when unproven.
    public func workspaceRelationships(storePath: String? = nil) -> [EntityRelationship] {
        var rels: [EntityRelationship] = []
        if relationshipConfidence == .verified, let ws = asRelationship(type: .belongsToWorkspace) {
            rels.append(ws)
        } else if relationshipConfidence == .inferred, let path = canonicalWorkspacePath {
            rels.append(EntityRelationship(
                type: .possibleWorkspaceContext,
                target: path,
                presence: workspaceExists == true ? .present : .unknown,
                confidence: .inferred
            ))
            rels.append(EntityRelationship(
                type: .belongsToWorkspace,
                target: path,
                presence: .unknown,
                confidence: .unknown
            ))
        } else {
            if let path = canonicalWorkspacePath {
                rels.append(EntityRelationship(
                    type: .belongsToWorkspace,
                    target: path,
                    presence: .unknown,
                    confidence: .unknown
                ))
            } else {
                rels.append(EntityRelationship(
                    type: .belongsToWorkspace,
                    target: rootKey ?? "unknown",
                    presence: .unknown,
                    confidence: .unknown
                ))
            }
        }
        if let storePath, let key = rootKey ?? workspaceID {
            rels.append(EntityRelationship(
                type: .associatedWithCursorStore,
                target: key,
                presence: .present,
                confidence: .verified
            ))
            rels.append(EntityRelationship(
                type: .observedInCursorContext,
                target: storePath,
                presence: .present,
                confidence: .verified
            ))
        } else if let store = asStoreAssociation() {
            rels.append(store)
        }
        return rels
    }
}

public struct CursorIdentityIndex: Sendable {
    /// workspaceStorage folder id → decoded folder path from workspace.json
    public var workspaceFolders: [String: String]
    /// store/root UUID or key → workspace folder path when explicitly referenced in metadata text
    public var explicitKeyToFolder: [String: String]
    /// lowercase basename of workspace folder → (workspaceID, path) — name hint only
    public var folderBasenameToWorkspace: [String: (id: String, path: String)]
    /// key → workspace path when secondary-index uniquely encodes that workspace path
    public var indexEncodedKeyToFolder: [String: String]
    /// key → reason when index mapping is ambiguous
    public var ambiguousKeys: Set<String>

    public init(
        workspaceFolders: [String: String] = [:],
        explicitKeyToFolder: [String: String] = [:],
        folderBasenameToWorkspace: [String: (id: String, path: String)] = [:],
        indexEncodedKeyToFolder: [String: String] = [:],
        ambiguousKeys: Set<String> = []
    ) {
        self.workspaceFolders = workspaceFolders
        self.explicitKeyToFolder = explicitKeyToFolder
        self.folderBasenameToWorkspace = folderBasenameToWorkspace
        self.indexEncodedKeyToFolder = indexEncodedKeyToFolder
        self.ambiguousKeys = ambiguousKeys
    }
}

/// Read-only Cursor identity bridge.
/// VERIFIED only from explicit metadata (UUID/key in JSON, or unique path encoding in secondary-index).
/// Folder-name / basename similarity alone stays INFERRED.
public enum CursorWorkspaceIdentityResolver {
    public static let indexProbeBytes = 256_000

    public static func buildIndex(home: String) -> CursorIdentityIndex {
        let root = "\(home)/Library/Application Support/Cursor/User/workspaceStorage"
        var folders: [String: String] = [:]
        var explicit: [String: String] = [:]
        var byBase: [String: (id: String, path: String)] = [:]
        var indexMap: [String: String] = [:]
        var ambiguous = Set<String>()

        let kids = ChildFolderEnumerator(maxChildren: 120).immediateDirectories(at: root)
        let storeIDs = ChildFolderEnumerator(maxChildren: 24).immediateDirectories(
            at: "\(home)/Library/Application Support/Cursor/snapshots/stores"
        ).map(\.name)
        let rootKeys = ChildFolderEnumerator(maxChildren: 40).immediateDirectories(
            at: "\(home)/Library/Application Support/Cursor/snapshots/roots"
        ).map(\.name)

        for kid in kids {
            let jsonPath = "\(kid.path)/workspace.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let folderURI = (obj["folder"] as? String) ?? ""
            let path = decodeFileURI(folderURI)
            guard !path.isEmpty else { continue }
            folders[kid.name] = path
            let base = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if !base.isEmpty {
                byBase[base] = (kid.name, path)
            }
            if let text = String(data: data, encoding: .utf8) {
                for id in storeIDs where text.contains(id) {
                    explicit[id] = path
                }
                for key in rootKeys where text.contains(key) {
                    explicit[key] = path
                }
            }
        }

        // P1.7: merge bounded explicit metadata discovery (workspaceMetadata / workspace.json IDs)
        let discovery = CursorExplicitMetadataResolver.discover(home: home)
        for (k, v) in discovery.explicitKeyToFolder {
            if let existing = explicit[k], existing != v {
                ambiguous.insert(k)
                explicit.removeValue(forKey: k)
            } else if !ambiguous.contains(k) {
                explicit[k] = v
            }
        }
        ambiguous.formUnion(discovery.ambiguousKeys)
        // stash discovery on thread-local style via lastDiscovery for reports
        Self.lastDiscovery = discovery.report

        // Bounded secondary-index path encoding probe (roots + stores)
        let probeTargets: [(String, String)] =
            rootKeys.map { ($0, "\(home)/Library/Application Support/Cursor/snapshots/roots/\($0)/secondary-index-baseline") }
            + storeIDs.map { ($0, "\(home)/Library/Application Support/Cursor/snapshots/stores/\($0)/secondary-index-baseline") }

        for (key, indexPath) in probeTargets {
            if explicit[key] != nil { continue }
            let hits = matchWorkspacesInIndex(indexPath: indexPath, workspaces: Array(folders.values))
            if hits.count == 1, let only = hits.first {
                indexMap[key] = only
            } else if hits.count > 1 {
                ambiguous.insert(key)
            }
        }

        return CursorIdentityIndex(
            workspaceFolders: folders,
            explicitKeyToFolder: explicit,
            folderBasenameToWorkspace: byBase,
            indexEncodedKeyToFolder: indexMap,
            ambiguousKeys: ambiguous
        )
    }

    /// Last discovery report from buildIndex (process-local).
    nonisolated(unsafe) public static var lastDiscovery: CursorMetadataDiscoveryReport?

    public static func sharedIndex(home: String) -> CursorIdentityIndex {
        if let cached = DetectorCatalog.sharedCursorIndex, DetectorCatalog.sharedCursorIndexHome == home {
            return cached
        }
        let built = buildIndex(home: home)
        DetectorCatalog.sharedCursorIndex = built
        DetectorCatalog.sharedCursorIndexHome = home
        return built
    }

    public static func resolveRoot(rootFolderName: String, home: String, index: CursorIdentityIndex) -> CursorWorkspaceIdentity {
        let markerKey = rootFolderName

        if let path = index.explicitKeyToFolder[rootFolderName] {
            return verifiedIdentity(
                path: path,
                rootKey: markerKey,
                index: index,
                source: .appMetadata,
                steps: ["metadata_artifact", "root_key_in_workspace_json", "uri_canonicalized", "target_exists_checked"]
            )
        }

        if index.ambiguousKeys.contains(rootFolderName) {
            return CursorWorkspaceIdentity(
                rootKey: markerKey,
                relationshipConfidence: .unknown,
                evidenceSource: .manifest,
                unknownReason: UnknownReasonCode.cursorRelationshipAmbiguous.rawValue,
                explicitMetadataReference: false,
                proofSteps: ["secondary_index_probed", "multiple_workspace_hits"]
            )
        }

        if let path = index.indexEncodedKeyToFolder[rootFolderName] {
            return verifiedIdentity(
                path: path,
                rootKey: markerKey,
                index: index,
                source: .manifest,
                steps: ["metadata_artifact", "secondary_index_unique_path", "uri_canonicalized", "target_exists_checked"]
            )
        }

        // Basename / folder-name guess → INFERRED only (never VERIFIED)
        let base = stripHashSuffix(rootFolderName).lowercased()
        if let hit = index.folderBasenameToWorkspace[base] {
            let exists = FileManager.default.fileExists(atPath: hit.path)
            return CursorWorkspaceIdentity(
                workspaceID: hit.id,
                rootKey: markerKey,
                canonicalWorkspacePath: hit.path,
                relationshipConfidence: .inferred,
                evidenceSource: .filesystemMetadata,
                unknownReason: exists
                    ? UnknownReasonCode.sourceRelationUnknown.rawValue
                    : UnknownReasonCode.cursorWorkspaceTargetNotFound.rawValue,
                explicitMetadataReference: false,
                workspaceExists: exists,
                proofSteps: ["basename_hint_only"]
            )
        }

        if let guessed = WorkspaceRelationshipResolver.inferredWorkspacePath(from: rootFolderName, home: home) {
            let exists = FileManager.default.fileExists(atPath: guessed)
            return CursorWorkspaceIdentity(
                rootKey: markerKey,
                canonicalWorkspacePath: guessed,
                relationshipConfidence: .inferred,
                evidenceSource: .filesystemMetadata,
                unknownReason: exists
                    ? UnknownReasonCode.sourceRelationUnknown.rawValue
                    : UnknownReasonCode.workspaceReferenceMissing.rawValue,
                explicitMetadataReference: false,
                workspaceExists: exists,
                proofSteps: ["folder_name_inference"]
            )
        }

        return CursorWorkspaceIdentity(
            rootKey: markerKey,
            relationshipConfidence: .unknown,
            evidenceSource: .unknown,
            unknownReason: UnknownReasonCode.cursorStoreUUIDNotReferenced.rawValue,
            explicitMetadataReference: false,
            proofSteps: ["no_explicit_metadata"]
        )
    }

    public static func resolveStore(storeID: String, index: CursorIdentityIndex) -> CursorWorkspaceIdentity {
        if let path = index.explicitKeyToFolder[storeID] {
            return verifiedIdentity(
                path: path,
                rootKey: storeID,
                index: index,
                source: .appMetadata,
                steps: ["metadata_artifact", "store_uuid_in_workspace_json", "uri_canonicalized", "target_exists_checked"]
            )
        }
        if index.ambiguousKeys.contains(storeID) {
            return CursorWorkspaceIdentity(
                rootKey: storeID,
                relationshipConfidence: .unknown,
                evidenceSource: .manifest,
                unknownReason: UnknownReasonCode.cursorRelationshipAmbiguous.rawValue,
                explicitMetadataReference: false,
                proofSteps: ["secondary_index_probed", "multiple_workspace_hits"]
            )
        }
        if let path = index.indexEncodedKeyToFolder[storeID] {
            return verifiedIdentity(
                path: path,
                rootKey: storeID,
                index: index,
                source: .manifest,
                steps: ["metadata_artifact", "secondary_index_unique_path", "uri_canonicalized", "target_exists_checked"]
            )
        }
        return CursorWorkspaceIdentity(
            rootKey: storeID,
            relationshipConfidence: .unknown,
            evidenceSource: .unknown,
            unknownReason: UnknownReasonCode.cursorStoreUUIDNotReferenced.rawValue,
            explicitMetadataReference: false,
            proofSteps: ["store_uuid_not_in_workspace_json", "secondary_index_no_unique_workspace"]
        )
    }

    static func verifiedIdentity(
        path: String,
        rootKey: String,
        index: CursorIdentityIndex,
        source: EvidenceSourceKind,
        steps: [String]
    ) -> CursorWorkspaceIdentity {
        let exists = FileManager.default.fileExists(atPath: path)
        // Explicit metadata + missing target → NOT VERIFIED (honest UNKNOWN)
        if !exists {
            return CursorWorkspaceIdentity(
                workspaceID: index.workspaceFolders.first { $0.value == path }?.key,
                rootKey: rootKey,
                canonicalWorkspacePath: path,
                relationshipConfidence: .unknown,
                evidenceSource: source,
                unknownReason: UnknownReasonCode.cursorWorkspaceTargetNotFound.rawValue,
                explicitMetadataReference: true,
                workspaceExists: false,
                proofSteps: steps + ["target_missing"]
            )
        }
        return CursorWorkspaceIdentity(
            workspaceID: index.workspaceFolders.first { $0.value == path }?.key,
            rootKey: rootKey,
            canonicalWorkspacePath: path,
            relationshipConfidence: .verified,
            evidenceSource: source,
            unknownReason: nil,
            explicitMetadataReference: true,
            workspaceExists: true,
            proofSteps: steps
        )
    }

    /// Bounded read of secondary-index; match known workspace paths by absolute or dash-encoded form.
    public static func matchWorkspacesInIndex(indexPath: String, workspaces: [String]) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: indexPath) else { return [] }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: indexProbeBytes)
        guard !data.isEmpty else { return [] }
        var hits: [String] = []
        for path in workspaces where !path.isEmpty {
            let abs = Data(path.utf8)
            let enc = Data(dashEncodePath(path).utf8)
            if data.range(of: abs) != nil || data.range(of: enc) != nil {
                hits.append(path)
            }
        }
        return hits
    }

    /// `/Users/tomi/AIGIG/my-portfolio` → `Users-tomi-AIGIG-my-portfolio`
    public static func dashEncodePath(_ path: String) -> String {
        path.split(separator: "/").joined(separator: "-")
    }

    public static func decodeFileURI(_ uri: String) -> String {
        uri.replacingOccurrences(of: "file://", with: "")
            .removingPercentEncoding ?? uri.replacingOccurrences(of: "file://", with: "")
    }

    public static func stripHashSuffix(_ name: String) -> String {
        if let range = name.range(of: "-[0-9a-fA-F]{6,}$", options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }
        return name
    }
}
