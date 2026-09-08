import Foundation

public enum SemanticKind: String, Codable, Sendable {
    case cache, log, model, session, history, settings, config
    case extensionData = "extension"
    case index, embedding, database, download, generated
    case workspaceState, userContent, unknown
}

public enum UnknownReasonCode: String, Codable, Sendable {
    case unknownNoRule = "UNKNOWN_NO_RULE"
    case unknownNoEvidence = "UNKNOWN_NO_EVIDENCE"
    case unknownVendor = "UNKNOWN_VENDOR"
    case unknownPath = "UNKNOWN_PATH"
    case unknownActiveState = "UNKNOWN_ACTIVE_STATE"
    case unknownSourceOfTruth = "UNKNOWN_SOURCE_OF_TRUTH"
    case unknownRegenerability = "UNKNOWN_REGENERABILITY"
    case unknownSyncState = "UNKNOWN_SYNC_STATE"
    case unknownMixedContent = "UNKNOWN_MIXED_CONTENT"
    case provenanceNoManifest = "PROVENANCE_NO_MANIFEST"
    case provenanceOwnerUnknown = "PROVENANCE_OWNER_UNKNOWN"
    case workspaceReferenceMissing = "WORKSPACE_REFERENCE_MISSING"
    case deviceMetadataUnavailable = "DEVICE_METADATA_UNAVAILABLE"
    case versionRelationUnknown = "VERSION_RELATION_UNKNOWN"
    case lifecycleMixedContent = "LIFECYCLE_MIXED_CONTENT"
    case lifecycleDatabaseUnknown = "LIFECYCLE_DATABASE_UNKNOWN"
    case activeStateUnknown = "ACTIVE_STATE_UNKNOWN"
    case sourceRelationUnknown = "SOURCE_RELATION_UNKNOWN"
    case productVersionUnknown = "PRODUCT_VERSION_UNKNOWN"
    case unknownEvidenceIncomplete = "UNKNOWN_EVIDENCE_INCOMPLETE"
    case unknownProcessObservation = "UNKNOWN_PROCESS_OBSERVATION"
    case unknownNoVendorRule = "UNKNOWN_NO_VENDOR_RULE"
    case unknownRemoteCopy = "UNKNOWN_REMOTE_COPY"
    case unknownManifest = "UNKNOWN_MANIFEST"
    case unknownCustomAsset = "UNKNOWN_CUSTOM_ASSET"
    case unknownProvider = "UNKNOWN_PROVIDER"
    case unknownDatabaseRole = "UNKNOWN_DATABASE_ROLE"
    case unknownWorkspaceRelation = "UNKNOWN_WORKSPACE_RELATION"
    case unknownVersionRelation = "UNKNOWN_VERSION_RELATION"
    case cursorMetadataMissing = "CURSOR_METADATA_MISSING"
    case cursorMetadataUnparseable = "CURSOR_METADATA_UNPARSEABLE"
    case cursorStoreUUIDNotReferenced = "CURSOR_STORE_UUID_NOT_REFERENCED"
    case cursorWorkspaceURIMissing = "CURSOR_WORKSPACE_URI_MISSING"
    case cursorWorkspacePathMissing = "CURSOR_WORKSPACE_PATH_MISSING"
    case cursorWorkspaceTargetNotFound = "CURSOR_WORKSPACE_TARGET_NOT_FOUND"
    case cursorRelationshipAmbiguous = "CURSOR_RELATIONSHIP_AMBIGUOUS"
    case proofBudgetExceeded = "PROOF_BUDGET_EXCEEDED"
    case proofTimeout = "PROOF_TIMEOUT"
    case processTimeout = "PROCESS_TIMEOUT"
    case processPermissionLimit = "PROCESS_PERMISSION_LIMIT"
    case lsofTimeout = "LSOF_TIMEOUT"
    case lsofPartialParse = "LSOF_PARTIAL_PARSE"
    case dbQueryLimitReached = "DB_QUERY_LIMIT_REACHED"
    case dbOpenFailed = "DB_OPEN_FAILED"
    case metadataNotPresent = "METADATA_NOT_PRESENT"
    case fileProviderUnavailable = "FILE_PROVIDER_UNAVAILABLE"
    case scanBudgetExceeded = "SCAN_BUDGET_EXCEEDED"

    public static func classify(decision: SafetyDecision, evidence: EvidenceBundle, entity: StorageEntity) -> UnknownReasonCode? {
        guard decision.safetyClass == .unknown else { return nil }
        if evidence.openFileHandle == .unknown || evidence.owningProcessRunning == .unknown {
            return .unknownActiveState
        }
        if evidence.regenerable == .unknown {
            return .unknownRegenerability
        }
        if evidence.sourceOfTruth == .unknown {
            return .unknownSourceOfTruth
        }
        if evidence.syncWouldDeleteRemote == .unknown, entity.kind == .cloudPlaceholder || entity.kind == .cloudLocalMaterialized {
            return .unknownSyncState
        }
        if decision.matchedRuleID == nil {
            return .unknownNoRule
        }
        if entity.kind == .unknown {
            return .unknownVendor
        }
        return .unknownNoEvidence
    }
}

public struct UnresolvedBucket: Codable, Sendable, Equatable {
    public var path: String
    public var exclusiveBytes: Int64
    public var resolution: ResolutionLevel
    public var domain: String
    public var product: String?
    public var reason: UnknownReasonCode
    public var nextDetector: String
}

public struct DomainSemanticCoverage: Codable, Sendable, Equatable {
    public var domain: String
    public var uniqueBytes: Int64
    public var l3PlusPercent: Double
    public var l4PlusPercent: Double
}

public enum SemanticDebt {
    public static let largeBucket: Int64 = 1_073_741_824

    public static func bytes(nodes: [AccountedNode]) -> Int64 {
        nodes.reduce(0) { sum, n in
            if n.resolution <= .l2Domain { return sum + n.exclusiveBytes }
            if n.resolution == .l3Product, n.exclusiveBytes >= largeBucket {
                return sum + n.exclusiveBytes
            }
            return sum
        }
    }
}

public enum SemanticReports {
    public static func domainCoverage(items: [ClassifiedItem]) -> [DomainSemanticCoverage] {
        let grouped = Dictionary(grouping: items, by: \.detected.domain)
        return grouped.keys.sorted().map { domain in
            let rows = grouped[domain] ?? []
            let unique = rows.reduce(Int64(0)) { $0 + $1.exclusiveBytes }
            let denom = max(unique, 1)
            let l3 = rows.filter { $0.resolution >= .l3Product }.reduce(Int64(0)) { $0 + $1.exclusiveBytes }
            let l4 = rows.filter { $0.resolution >= .l4SemanticEntity }.reduce(Int64(0)) { $0 + $1.exclusiveBytes }
            return DomainSemanticCoverage(
                domain: domain,
                uniqueBytes: unique,
                l3PlusPercent: ByteAccountant.coverage(uniqueBytes: l3, scannedBytes: denom),
                l4PlusPercent: ByteAccountant.coverage(uniqueBytes: l4, scannedBytes: denom)
            )
        }
    }

    public static func largestUnresolved(items: [ClassifiedItem], limit: Int = 20) -> [UnresolvedBucket] {
        items
            .filter { $0.resolution <= .l3Product }
            .sorted { $0.exclusiveBytes > $1.exclusiveBytes }
            .prefix(limit)
            .map { item in
                let reason: UnknownReasonCode
                if item.resolution <= .l2Domain { reason = .unknownPath }
                else if item.exclusiveBytes >= SemanticDebt.largeBucket { reason = .unknownMixedContent }
                else { reason = item.unknownReason ?? .unknownNoRule }
                let next: String
                if item.detected.domain == "AI Tools" { next = "AIToolDeepDetector" }
                else if item.detected.entity.path.contains("/Containers/") { next = "ContainerDeepDetector" }
                else if item.detected.entity.path.contains("Application Support") { next = "AppSupportDeepDetector" }
                else { next = "semantic-entity-detector" }
                return UnresolvedBucket(
                    path: item.detected.entity.path,
                    exclusiveBytes: item.exclusiveBytes,
                    resolution: item.resolution,
                    domain: item.detected.domain,
                    product: item.detected.entity.subcategory,
                    reason: reason,
                    nextDetector: next
                )
            }
    }
}
