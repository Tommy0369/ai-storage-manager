import Foundation

public enum HistoricalDerivedDataState: String, Codable, Sendable {
    case stillExists = "STILL_EXISTS"
    case noLongerExists = "NO_LONGER_EXISTS"
    case pathChanged = "PATH_CHANGED"
    case metadataChanged = "METADATA_CHANGED"
    case sourceWorkspaceMissing = "SOURCE_WORKSPACE_MISSING"
    case sourceWorkspaceMoved = "SOURCE_WORKSPACE_MOVED"
    case inaccessible = "INACCESSIBLE"
    case unknown = "UNKNOWN"
}

public struct HistoricalDerivedDataCheck: Codable, Sendable, Equatable {
    public var path: String
    public var entityIDHint: String
    public var classification: String
    public var exists: Bool
    public var isDirectory: Bool
    public var infoPlistPresent: Bool
    public var workspacePathPresent: Bool
    public var workspacePath: String?
    public var workspaceExists: Bool?
}

public struct DerivedDataSurfaceFunnelEntry: Codable, Sendable, Equatable {
    public var path: String
    public var childName: String
    public var filesystemObserved: Bool
    public var scannerObserved: Bool
    public var detectorCandidate: Bool
    public var detectorMatched: Bool
    public var entityEmitted: Bool
    public var entityDeduplicated: Bool
    public var entityDroppedReason: String?
    public var proofCandidate: Bool
    public var proofAttempted: Bool
    public var proofResult: String?
    public var reportSurfaced: Bool
    public var finalEntityID: String?
    public var infoPlistPresent: Bool
    public var workspacePathPresent: Bool
    public var workspaceExists: Bool?
    public var measurementKnown: Bool?
}

public struct DerivedDataSurfaceFunnelReport: Codable, Sendable, Equatable {
    public var derivedDataRoot: String
    public var rootExists: Bool
    public var filesystemChildCount: Int
    public var enumerationBounded: Bool
    public var enumerationMaxChildren: Int
    public var enumerationRuntimeMs: Int
    public var historicalChecks: [HistoricalDerivedDataCheck]
    public var entries: [DerivedDataSurfaceFunnelEntry]
    public var rootEntityID: String?
    public var rootEntitySurfaced: Bool
    public var concreteSemanticEntityCount: Int
    public var scannerObservedChildCount: Int
    public var detectorMatchedCount: Int
    public var entityEmittedCount: Int
    public var proofCandidateCount: Int
    public var proofAttemptedCount: Int
    public var reportSurfacedCount: Int
}

public struct DerivedDataDetectorRegistrationEntry: Codable, Sendable, Equatable {
    public var detectorID: String
    public var tier: String
    public var enabled: Bool
    public var proofTargetRequired: String?
    public var maxChildren: Int?
    public var defaultScanIncludes: Bool
    public var lastMatchCount: Int
    public var lastRuntimeMs: Int
}

public struct DerivedDataDetectorRegistrationReport: Codable, Sendable, Equatable {
    public var proofTargets: [String]
    public var defaultScanIncludesDerivedDataProof: Bool
    public var rootDetectorID: String
    public var proofDetectorID: String
    public var entries: [DerivedDataDetectorRegistrationEntry]
    public var catalogOptInProofDetectors: [String]
}

public enum DerivedDataSurfaceRootCause: String, Codable, Sendable {
    case realStateChanged = "REAL_STATE_CHANGED"
    case detectorRegression = "DETECTOR_REGRESSION"
    case catalogRoutingRegression = "CATALOG_ROUTING_REGRESSION"
    case entityDedupRegression = "ENTITY_DEDUP_REGRESSION"
    case scannerVisibilityRegression = "SCANNER_VISIBILITY_REGRESSION"
    case proofCandidateRegression = "PROOF_CANDIDATE_REGRESSION"
    case reportingRegression = "REPORTING_REGRESSION"
    case expectedCurrentBehavior = "EXPECTED_CURRENT_BEHAVIOR"
    case multipleCauses = "MULTIPLE_CAUSES"
}

public struct DerivedDataSurfaceRootCauseReport: Codable, Sendable, Equatable {
    public var classification: String
    public var secondaryClassifications: [String]
    public var explanation: String
    public var evidence: [String]
    public var filesystemChildCount: Int
    public var historicalEntitiesStillExist: Int
    public var detectorRan: Bool
    public var detectorMatchCount: Int
    public var architecturalFixRequired: Bool
    public var architecturalFixMade: Bool
    public var p21GateImplication: String
}

public enum DerivedDataSurfaceAnalyzer {
    public static let historicalEntityHints: [(pathSuffix: String, entityID: String)] = [
        ("Runner-ecnbmvkdltyrtnevcspalufxjhdq", "xcode.deriveddata.Runner-ecnbmvkdltyrtnevcspalufxjhdq"),
        ("Runner-ckovnoskqurramhgydmrtirfscgd", "xcode.deriveddata.Runner-ckovnoskqurramhgydmrtirfscgd"),
    ]

    public static let skipChildNames: Set<String> = [
        "ModuleCache.noindex", "SourcePackages", "CompilationCache.noindex", "SymbolCache.noindex",
    ]

    public static func analyze(
        home: String,
        items: [ClassifiedItem],
        proofTargets: Set<String>,
        catalogRuntime: DetectorCatalogRuntimeReport?,
        verificationBacklog: EntityVerificationBacklogReport,
        scanner: ReadOnlyStorageScanner = ReadOnlyStorageScanner()
    ) -> (funnel: DerivedDataSurfaceFunnelReport, registration: DerivedDataDetectorRegistrationReport, rootCause: DerivedDataSurfaceRootCauseReport) {
        let root = "\(home)/Library/Developer/Xcode/DerivedData"
        let rootExists = FileManager.default.fileExists(atPath: root)
        let enumStarted = Date()
        let fsChildren = rootExists
            ? ChildFolderEnumerator(maxChildren: 64).immediateDirectories(at: root, caller: "DerivedDataSurfaceAnalyzer")
            : []
        let enumMs = Int(Date().timeIntervalSince(enumStarted) * 1000)
        let concreteFS = fsChildren.filter { !skipChildNames.contains($0.name) }

        let historical = historicalEntityHints.map { checkHistorical(home: home, suffix: $0.pathSuffix, entityID: $0.entityID) }

        let proofDetector = XcodeDerivedDataProofDetector(maxChildren: 4)
        let detectorStarted = Date()
        let detectorEntities = proofTargets.contains("derived-data")
            ? proofDetector.detect(home: home, scanner: scanner)
            : []
        _ = Int(Date().timeIntervalSince(detectorStarted) * 1000)

        let itemByPath = Dictionary(uniqueKeysWithValues: items.map {
            ((($0.detected.entity.path as NSString).standardizingPath), $0)
        })
        let backlogByID = Dictionary(grouping: verificationBacklog.entries, by: \.entityID)

        var entries: [DerivedDataSurfaceFunnelEntry] = []
        for child in concreteFS {
            let stdPath = (child.path as NSString).standardizingPath
            let detectorHit = detectorEntities.first { ($0.entity.path as NSString).standardizingPath == stdPath }
            let item = itemByPath[stdPath]
            let infoPath = "\(child.path)/info.plist"
            let infoPresent = FileManager.default.fileExists(atPath: infoPath)
            var wsPath: String?
            if infoPresent { wsPath = XcodeDerivedDataProofDetector.readWorkspacePath(infoPath) }
            let wsExists = wsPath.map { FileManager.default.fileExists(atPath: $0) }
            let entityID = detectorHit?.entity.id ?? item?.detected.entity.id
            let backlogEntries = entityID.flatMap { backlogByID[$0] } ?? []
            let proofAttempted = backlogEntries.contains { $0.attempted }
            let proofResult = backlogEntries.first.map { $0.result }

            entries.append(DerivedDataSurfaceFunnelEntry(
                path: child.path,
                childName: child.name,
                filesystemObserved: true,
                scannerObserved: item != nil || detectorHit != nil,
                detectorCandidate: true,
                detectorMatched: detectorHit != nil,
                entityEmitted: detectorHit != nil,
                entityDeduplicated: detectorHit == nil && item == nil,
                entityDroppedReason: dropReason(detectorHit: detectorHit, item: item, infoPresent: infoPresent),
                proofCandidate: !backlogEntries.isEmpty,
                proofAttempted: proofAttempted,
                proofResult: proofResult,
                reportSurfaced: item != nil,
                finalEntityID: entityID,
                infoPlistPresent: infoPresent,
                workspacePathPresent: wsPath != nil,
                workspaceExists: wsExists,
                measurementKnown: item.map { $0.exclusiveBytes > 0 || $0.inclusiveBytes > 0 }
            ))
        }

        let rootItem = items.first {
            $0.detected.entity.id == "xcode.derived_data"
                || ($0.detected.entity.path as NSString).standardizingPath == (root as NSString).standardizingPath
        }

        let funnel = DerivedDataSurfaceFunnelReport(
            derivedDataRoot: root,
            rootExists: rootExists,
            filesystemChildCount: concreteFS.count,
            enumerationBounded: true,
            enumerationMaxChildren: 64,
            enumerationRuntimeMs: enumMs,
            historicalChecks: historical,
            entries: entries.sorted { $0.path < $1.path },
            rootEntityID: rootItem?.detected.entity.id,
            rootEntitySurfaced: rootItem != nil,
            concreteSemanticEntityCount: items.filter { isConcreteDerivedDataChild($0) }.count,
            scannerObservedChildCount: entries.filter(\.scannerObserved).count,
            detectorMatchedCount: entries.filter(\.detectorMatched).count,
            entityEmittedCount: entries.filter(\.entityEmitted).count,
            proofCandidateCount: entries.filter(\.proofCandidate).count,
            proofAttemptedCount: entries.filter(\.proofAttempted).count,
            reportSurfacedCount: entries.filter(\.reportSurfaced).count
        )

        let registration = buildRegistration(proofTargets: proofTargets, catalogRuntime: catalogRuntime, proofDetector: proofDetector)
        let rootCause = classifyRootCause(funnel: funnel, registration: registration, catalogRuntime: catalogRuntime)

        return (funnel, registration, rootCause)
    }

    static func checkHistorical(home: String, suffix: String, entityID: String) -> HistoricalDerivedDataCheck {
        let path = "\(home)/Library/Developer/Xcode/DerivedData/\(suffix)"
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let infoPath = "\(path)/info.plist"
        let infoPresent = exists && FileManager.default.fileExists(atPath: infoPath)
        var wsPath: String?
        if infoPresent { wsPath = XcodeDerivedDataProofDetector.readWorkspacePath(infoPath) }
        let wsExists = wsPath.map { FileManager.default.fileExists(atPath: $0) }

        let classification: HistoricalDerivedDataState
        if !exists {
            classification = .noLongerExists
        } else if infoPresent, let wsPath, wsExists == false {
            classification = .sourceWorkspaceMissing
        } else if infoPresent, wsPath == nil {
            classification = .metadataChanged
        } else if exists, isDir.boolValue {
            classification = .stillExists
        } else {
            classification = .unknown
        }

        return HistoricalDerivedDataCheck(
            path: path,
            entityIDHint: entityID,
            classification: classification.rawValue,
            exists: exists,
            isDirectory: isDir.boolValue,
            infoPlistPresent: infoPresent,
            workspacePathPresent: wsPath != nil,
            workspacePath: wsPath,
            workspaceExists: wsExists
        )
    }

    static func dropReason(detectorHit: DetectedEntity?, item: ClassifiedItem?, infoPresent: Bool) -> String? {
        if detectorHit != nil, item != nil { return nil }
        if detectorHit != nil, item == nil { return "EMITTED_NOT_IN_FINAL_ITEMS" }
        if detectorHit == nil, item != nil { return "ITEM_WITHOUT_PROOF_DETECTOR" }
        if !infoPresent { return "NO_INFO_PLIST_NOT_PROOF_INSTANCE" }
        return "NOT_OBSERVED_BY_PROOF_DETECTOR"
    }

    static func isConcreteDerivedDataChild(_ item: ClassifiedItem) -> Bool {
        let path = item.detected.entity.path.lowercased()
        guard path.contains("deriveddata") else { return false }
        if item.detected.entity.id == "xcode.derived_data" { return false }
        if path.hasSuffix("/deriveddata") { return false }
        return item.detected.annotation?.semanticType == "XCODE_DERIVEDDATA_INSTANCE"
            || item.detected.entity.id.hasPrefix("xcode.deriveddata.")
    }

    static func buildRegistration(
        proofTargets: Set<String>,
        catalogRuntime: DetectorCatalogRuntimeReport?,
        proofDetector: XcodeDerivedDataProofDetector
    ) -> DerivedDataDetectorRegistrationReport {
        let includesProof = proofTargets.contains("derived-data")
        let proofStat = catalogRuntime?.perDetector.first { $0.detectorID == "XcodeDerivedDataProofDetector" }
        return DerivedDataDetectorRegistrationReport(
            proofTargets: Array(proofTargets).sorted(),
            defaultScanIncludesDerivedDataProof: includesProof,
            rootDetectorID: "XcodeDetector",
            proofDetectorID: "XcodeDerivedDataProofDetector",
            entries: [
                DerivedDataDetectorRegistrationEntry(
                    detectorID: "XcodeDetector",
                    tier: "CORE",
                    enabled: true,
                    proofTargetRequired: nil,
                    maxChildren: nil,
                    defaultScanIncludes: true,
                    lastMatchCount: catalogRuntime?.perDetector.first { $0.detectorID == "XcodeDetector" }?.matchCount ?? 0,
                    lastRuntimeMs: catalogRuntime?.perDetector.first { $0.detectorID == "XcodeDetector" }?.totalDurationMs ?? 0
                ),
                DerivedDataDetectorRegistrationEntry(
                    detectorID: "XcodeDerivedDataProofDetector",
                    tier: "OPT_IN_PROOF",
                    enabled: includesProof,
                    proofTargetRequired: "derived-data",
                    maxChildren: proofDetector.maxChildren,
                    defaultScanIncludes: includesProof,
                    lastMatchCount: proofStat?.matchCount ?? 0,
                    lastRuntimeMs: proofStat?.totalDurationMs ?? 0
                ),
            ],
            catalogOptInProofDetectors: catalogRuntime?.optInProofDetectors ?? ["XcodeDerivedDataProofDetector"]
        )
    }

    static func classifyRootCause(
        funnel: DerivedDataSurfaceFunnelReport,
        registration: DerivedDataDetectorRegistrationReport,
        catalogRuntime: DetectorCatalogRuntimeReport?
    ) -> DerivedDataSurfaceRootCauseReport {
        var secondary: [String] = []
        var evidence: [String] = []
        var fixRequired = false

        let histExist = funnel.historicalChecks.filter(\.exists).count
        let fsCount = funnel.filesystemChildCount
        let detectorMatch = registration.entries.first { $0.detectorID == "XcodeDerivedDataProofDetector" }?.lastMatchCount ?? 0
        let detectorRan = catalogRuntime?.optInProofDetectors.contains("XcodeDerivedDataProofDetector") ?? registration.defaultScanIncludesDerivedDataProof

        evidence.append("filesystem_child_count=\(fsCount)")
        evidence.append("historical_still_exist=\(histExist)/\(funnel.historicalChecks.count)")
        evidence.append("proof_detector_match_count=\(detectorMatch)")
        evidence.append("concrete_semantic_entities=\(funnel.concreteSemanticEntityCount)")
        evidence.append("root_entity_surfaced=\(funnel.rootEntitySurfaced)")

        var primary: DerivedDataSurfaceRootCause

        if fsCount == 0, histExist == 0 {
            primary = .realStateChanged
            secondary.append(DerivedDataSurfaceRootCause.expectedCurrentBehavior.rawValue)
            evidence.append("DerivedData directory empty — no Product-hash children on disk")
            evidence.append("Historical Runner instances classified NO_LONGER_EXISTS")
        } else if fsCount > 0, detectorMatch == 0, registration.defaultScanIncludesDerivedDataProof {
            primary = .detectorRegression
            fixRequired = true
            evidence.append("Filesystem children exist but proof detector emitted zero entities")
        } else if fsCount > 0, detectorMatch > 0, funnel.reportSurfacedCount == 0 {
            primary = .reportingRegression
            secondary.append(DerivedDataSurfaceRootCause.entityDedupRegression.rawValue)
            fixRequired = true
            evidence.append("Detector emitted entities but none reached final items report")
        } else if fsCount > 0, funnel.detectorMatchedCount < fsCount {
            primary = .scannerVisibilityRegression
            secondary.append(DerivedDataSurfaceRootCause.catalogRoutingRegression.rawValue)
            evidence.append("Partial child surfacing — bounded enumeration or skip list may apply")
        } else if !detectorRan {
            primary = .catalogRoutingRegression
            fixRequired = true
            evidence.append("Proof detector not registered for current scan mode")
        } else if fsCount > 0, funnel.proofCandidateCount == 0 {
            primary = .proofCandidateRegression
            fixRequired = true
            evidence.append("Surfaced children did not become verification proof candidates")
        } else {
            primary = .expectedCurrentBehavior
            evidence.append("Surfacing pipeline consistent with observed filesystem")
        }

        let explanation: String
        switch primary {
        case .realStateChanged:
            explanation = "Concrete DerivedData proof directories no longer exist on this Mac. Empty DerivedData root with root-only semantic entity is expected; not a detector regression."
        case .detectorRegression:
            explanation = "Filesystem shows DerivedData children but XcodeDerivedDataProofDetector did not emit matching entities."
        case .catalogRoutingRegression:
            explanation = "DerivedData proof detector routing or proofTargets misconfigured for default scan."
        case .entityDedupRegression:
            explanation = "Proof entities emitted but lost before final catalog/report assembly."
        case .scannerVisibilityRegression:
            explanation = "Some filesystem children were not observed by scanner/detector path."
        case .proofCandidateRegression:
            explanation = "Semantic entities surfaced but VerificationCandidateBuilder did not enqueue proof."
        case .reportingRegression:
            explanation = "Entities detected but absent from Case Study items output."
        case .expectedCurrentBehavior:
            explanation = "Observed surfacing matches filesystem and detector outputs."
        case .multipleCauses:
            explanation = "Multiple independent surfacing issues detected."
        }

        let gateImplication = fsCount == 0
            ? "P2.1_GATE remains BLOCKED_BY_REAL_EVIDENCE — NO_CURRENT_REAL_DERIVEDDATA_PROOF_ENTITY"
            : (funnel.concreteSemanticEntityCount == 0
                ? "P2.1_GATE blocked pending surfacing fix or proof completion"
                : "Re-evaluate DerivedData mutation readiness funnel")

        return DerivedDataSurfaceRootCauseReport(
            classification: primary.rawValue,
            secondaryClassifications: secondary,
            explanation: explanation,
            evidence: evidence,
            filesystemChildCount: fsCount,
            historicalEntitiesStillExist: histExist,
            detectorRan: detectorRan,
            detectorMatchCount: detectorMatch,
            architecturalFixRequired: fixRequired,
            architecturalFixMade: false,
            p21GateImplication: gateImplication
        )
    }
}
