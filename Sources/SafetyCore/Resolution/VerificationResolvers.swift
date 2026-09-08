import Foundation

public enum SourceOfTruthResolver {
    public static func resolve(
        entity: StorageEntity,
        annotation: DetectionAnnotation?,
        evidence: EvidenceBundle
    ) -> ObservationRecord {
        let role = annotation?.lifecycle.role
        let kind = entity.kind
        let path = entity.path.lowercased()

        // Strong TRUE signals — filesystem / lifecycle structure
        if kind == .userOriginal || kind == .credentials || kind == .gitHistory {
            return ObservationRecord(
                value: .true,
                confidence: .verified,
                completeness: .complete,
                source: .filesystemMetadata,
                reasonCode: "USER_OR_AUTHORITATIVE_KIND"
            )
        }
        if role == .userContent || role == .backup {
            return ObservationRecord(
                value: .true,
                confidence: .verified,
                completeness: .complete,
                source: .relationshipMetadata,
                reasonCode: role == .backup ? "BACKUP_RECOVERY_COPY" : "USER_CONTENT_ROLE"
            )
        }
        if role == .userConfiguration, path.contains("preferences") || path.contains("settings") || path.hasSuffix(".claude") {
            return ObservationRecord(
                value: .true,
                confidence: .verified,
                completeness: .complete,
                source: .filesystemMetadata,
                reasonCode: "USER_CONFIGURATION"
            )
        }
        if path.contains("/documents/") || path.contains("/pictures/") || path.contains("/movies/") {
            return ObservationRecord(
                value: .true,
                confidence: .verified,
                completeness: .complete,
                source: .filesystemMetadata,
                reasonCode: "USER_LIBRARY_PATH"
            )
        }
        if path.contains("voicememos") && path.contains("/recordings") {
            return ObservationRecord(
                value: .true,
                confidence: .verified,
                completeness: .complete,
                source: .filesystemMetadata,
                reasonCode: "VOICE_MEMO_ORIGINAL"
            )
        }

        // Strong FALSE requires verified source relationship — never generatedBy / path alone.
        // generatedBy(Xcode) is ubiquitous; SOT FALSE needs derivedFrom or belongsToWorkspace PRESENT.
        let hasVerifiedSourceRelation = annotation?.relationships.contains {
            ($0.type == .derivedFrom || $0.type == .belongsToWorkspace)
                && $0.confidence == .verified
                && $0.presence == .present
        } == true
        if hasVerifiedSourceRelation, role == .cache || role == .temporary || role == .generatedArtifact || role == .log {
            return ObservationRecord(
                value: .false,
                confidence: .verified,
                completeness: .complete,
                source: .relationshipMetadata,
                reasonCode: "VERIFIED_DERIVED_ARTIFACT"
            )
        }

        // Database / snapshot / model / staging alone → UNKNOWN
        if role == .database || role == .snapshot || role == .model || role == .runtime || role == .mixed {
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .unknown,
                reasonCode: UnknownReasonCode.lifecycleDatabaseUnknown.rawValue
            )
        }
        if path.contains("cache") || path.contains("snapshot") || path.contains("staging") {
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .unknown,
                reasonCode: UnknownReasonCode.unknownSourceOfTruth.rawValue
            )
        }
        _ = evidence
        return ObservationRecord(
            value: .unknown,
            confidence: .unknown,
            completeness: .unknown,
            source: .unknown,
            reasonCode: UnknownReasonCode.unknownSourceOfTruth.rawValue
        )
    }
}

public enum RegenerabilityResolver {
    public static func resolve(
        entity: StorageEntity,
        annotation: DetectionAnnotation?,
        evidence: EvidenceBundle,
        sourceOfTruth: ObservationRecord
    ) -> ObservationRecord {
        let path = entity.path
        let lower = path.lowercased()
        let role = annotation?.lifecycle.role

        // Path alone never enough
        if lower.contains("deriveddata") {
            let hasVerifiedDerived = annotation?.relationships.contains {
                ($0.type == .derivedFrom || $0.type == .belongsToWorkspace)
                    && $0.confidence == .verified
                    && $0.presence == .present
            } == true
            let sourceOK = evidence.sourceProjectExists == .true
                && (evidence.predicateConfidence["source_project_exists"] == .verified || hasVerifiedDerived)
            let sotFalseVerified = sourceOfTruth.value == .false && sourceOfTruth.confidence == .verified
            if hasVerifiedDerived, sourceOK || hasVerifiedDerived, evidence.isSymlink == .false, sotFalseVerified {
                return ObservationRecord(
                    value: .true,
                    confidence: .verified,
                    completeness: .complete,
                    source: .vendorRule,
                    reasonCode: "XCODE_DERIVEDDATA_REBUILD"
                )
            }
            if !hasVerifiedDerived, !sourceOK {
                return ObservationRecord(
                    value: .unknown,
                    confidence: .unknown,
                    completeness: .partial,
                    source: .vendorRule,
                    reasonCode: UnknownReasonCode.sourceRelationUnknown.rawValue
                )
            }
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .vendorRule,
                reasonCode: UnknownReasonCode.unknownRegenerability.rawValue
            )
        }

        if lower.contains("node_modules") {
            let hasLocalSignal = annotation?.unknownReasons.contains(UnknownReasonCode.unknownCustomAsset.rawValue) == true
            let hasVerifiedDerived = annotation?.relationships.contains {
                $0.type == .derivedFrom && $0.confidence == .verified && $0.presence == .present
            } == true
            if evidence.manifestExists == .true,
               evidence.lockfileExists == .true,
               evidence.sourceProjectExists == .true,
               hasVerifiedDerived,
               !hasLocalSignal {
                return ObservationRecord(
                    value: .true,
                    confidence: .verified,
                    completeness: .complete,
                    source: .vendorRule,
                    reasonCode: "NODE_MODULES_FROM_LOCKFILE"
                )
            }
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .vendorRule,
                reasonCode: hasLocalSignal
                    ? UnknownReasonCode.unknownCustomAsset.rawValue
                    : (evidence.lockfileExists != .true ? "UNKNOWN_MANIFEST" : UnknownReasonCode.unknownRegenerability.rawValue)
            )
        }

        // Authoritative / user content → regenerable false VERIFIED
        if sourceOfTruth.value == .true, sourceOfTruth.confidence == .verified {
            return ObservationRecord(
                value: .false,
                confidence: .verified,
                completeness: .complete,
                source: .relationshipMetadata,
                reasonCode: "SOURCE_OF_TRUTH_NOT_REGENERABLE"
            )
        }

        // Snapshot / HF cache / staging name alone → UNKNOWN
        if role == .snapshot || lower.contains("/snapshots/") || lower.contains("huggingface") || lower.contains("/staging") {
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .unknown,
                reasonCode: UnknownReasonCode.unknownRegenerability.rawValue
            )
        }

        if role == .runtime || lower.contains("rootfs.img") || lower.contains("vm_bundles") {
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .unknown,
                reasonCode: UnknownReasonCode.unknownRegenerability.rawValue
            )
        }

        return ObservationRecord(
            value: .unknown,
            confidence: .unknown,
            completeness: .unknown,
            source: .unknown,
            reasonCode: UnknownReasonCode.unknownRegenerability.rawValue
        )
    }

    static func climbProject(from path: String) -> String {
        var url = URL(fileURLWithPath: path)
        for _ in 0..<8 {
            let pkg = url.appendingPathComponent("Package.swift").path
            let xcode = url.pathExtension == "xcodeproj" || url.pathExtension == "xcworkspace"
            if FileManager.default.fileExists(atPath: pkg) || xcode { return url.path }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return ""
    }
}

public enum ActiveStateResolver {
    public static func resolve(
        entityPath: String,
        associatedProcesses: [String],
        processes: any ProcessRunningChecker,
        handles: any OpenHandleChecker,
        processCompleteness: ObservationCompleteness,
        handleCompleteness: ObservationCompleteness,
        relatedPaths: [String] = []
    ) -> (ObservedActiveState, EvidenceConfidence, ObservationCompleteness, [String]) {
        var reasons: [String] = []
        let paths = [entityPath] + relatedPaths
        var open: PredicateValue = .false
        for p in paths {
            let v = handles.hasOpenHandles(path: p)
            if v == .true { open = .true; break }
            if v == .unknown { open = .unknown }
        }
        if handleCompleteness != .complete, open == .unknown {
            reasons.append(UnknownReasonCode.unknownEvidenceIncomplete.rawValue)
            return (.unknown, .unknown, handleCompleteness, reasons)
        }
        if open == .true {
            return (.active, .verified, .complete, [])
        }

        // Exact path referenced in process command lines (single snapshot)
        if let snap = processes as? ProcessTableSnapshot, snap.completeness == .complete {
            if paths.contains(where: { snap.referencesPath($0) }) {
                return (.active, .verified, .complete, [])
            }
        }

        let running: PredicateValue
        if associatedProcesses.isEmpty {
            running = .unknown
            reasons.append(UnknownReasonCode.unknownProcessObservation.rawValue)
        } else if processCompleteness != .complete {
            running = .unknown
            reasons.append(UnknownReasonCode.unknownEvidenceIncomplete.rawValue)
        } else {
            running = processes.isRunning(executableNames: associatedProcesses)
        }

        if running == .true, open == .false, handleCompleteness == .complete {
            reasons.append(UnknownReasonCode.unknownActiveState.rawValue)
            return (.unknown, .inferred, .partial, reasons)
        }

        if processCompleteness == .complete, handleCompleteness == .complete,
           running == .false, open == .false, !associatedProcesses.isEmpty {
            return (.inactive, .verified, .complete, [])
        }

        reasons.append(UnknownReasonCode.unknownActiveState.rawValue)
        return (.unknown, .unknown, .partial, reasons)
    }
}
