import Foundation

public struct VerificationAttemptRecord: Equatable, Sendable {
    public var key: String
    public var state: VerificationAttemptState
    public var outcome: VerificationStrategyOutcome
}

public enum VerificationStrategies {
    public static func attempt(
        strategy: VerificationStrategyID,
        entity: DetectedEntity,
        evidence: inout EvidenceBundle,
        verification: inout VerificationAnnotation,
        context: VerificationLoopContext,
        budgetMs: Int
    ) -> VerificationStrategyResult {
        let started = Date()
        let claim = primaryClaim(for: strategy)
        var result: VerificationStrategyResult

        switch strategy {
        case .resolverSourceOfTruth:
            let sot = SourceOfTruthResolver.resolve(entity: entity.entity, annotation: entity.annotation, evidence: evidence)
            evidence.sourceOfTruth = sot.value
            evidence.predicateConfidence["not_source_of_truth"] = sot.confidence
            verification.sourceOfTruth = sot
            result = mapObservation(sot, strategy: strategy, entityID: entity.entity.id, claim: .sourceOfTruth, started: started)

        case .resolverRegenerability:
            let sot = verification.sourceOfTruth
            if sot.value == .unknown, sot.confidence != .verified,
               entity.entity.path.lowercased().contains("deriveddata") || entity.entity.path.lowercased().contains("node_modules") {
                result = blockedResult(strategy: strategy, entityID: entity.entity.id, claim: .regenerability, reason: "DERIVED_FROM_OR_SOT_UNKNOWN")
            } else {
                let regen = RegenerabilityResolver.resolve(
                    entity: entity.entity,
                    annotation: entity.annotation,
                    evidence: evidence,
                    sourceOfTruth: sot
                )
                evidence.regenerable = regen.value
                evidence.predicateConfidence["regenerable"] = regen.confidence
                verification.regenerable = regen
                verification.reconstructionMechanism = regen.reasonCode
                result = mapObservation(regen, strategy: strategy, entityID: entity.entity.id, claim: .regenerability, started: started)
            }

        case .resolverActiveState:
            let related = claudeRelatedPaths(entity: entity)
            let (active, conf, comp, reasons) = ActiveStateResolver.resolve(
                entityPath: entity.entity.path,
                associatedProcesses: entity.associatedProcesses,
                processes: context.processes,
                handles: context.handles,
                processCompleteness: entity.associatedProcesses.isEmpty ? .unknown : context.processCompleteness,
                handleCompleteness: context.handleCompleteness,
                relatedPaths: related
            )
            verification.activeState = active
            verification.activeStateConfidence = conf
            verification.activeStateCompleteness = comp
            verification.unknownReasons.append(contentsOf: reasons)
            result = VerificationStrategyResult(
                strategyID: strategy,
                entityID: entity.entity.id,
                claim: .activeState,
                outcome: conf == .verified ? .verified : (conf == .inferred ? .inferred : .unknown),
                runtimeMs: msSince(started),
                budgetUsedMs: msSince(started),
                reasonCodes: reasons,
                supportingEvidence: ["PROCESS_SNAPSHOT", "OPEN_FILE_SNAPSHOT"],
                failedRequirements: [],
                unknownRequirements: conf == .verified ? [] : reasons
            )

        case .derivedData:
            result = derivedDataProof(entity: entity, evidence: &evidence, verification: &verification, started: started)

        case .claudeVMActive:
            result = claudeActiveProof(entity: entity, evidence: &evidence, verification: &verification, context: context, started: started)

        case .cursorMetadata, .workspaceRelationship:
            result = cursorRelationshipProof(entity: entity, started: started)

        case .nodeModules:
            let regen = RegenerabilityResolver.resolve(
                entity: entity.entity,
                annotation: entity.annotation,
                evidence: evidence,
                sourceOfTruth: verification.sourceOfTruth
            )
            verification.regenerable = regen
            result = mapObservation(regen, strategy: strategy, entityID: entity.entity.id, claim: .regenerability, started: started)

        case .fileProvider:
            if evidence.cloudFileProvider == .true {
                result = VerificationStrategyResult(
                    strategyID: strategy,
                    entityID: entity.entity.id,
                    claim: .remoteCopyExists,
                    outcome: .unknown,
                    runtimeMs: msSince(started),
                    budgetUsedMs: msSince(started),
                    reasonCodes: ["UNKNOWN_NO_PROVIDER_EVIDENCE"],
                    supportingEvidence: ["FILE_PROVIDER_FLAG"],
                    failedRequirements: [],
                    unknownRequirements: ["provider_metadata_unavailable"]
                )
            } else {
                result = blockedResult(strategy: strategy, entityID: entity.entity.id, claim: .remoteCopyExists, reason: "NOT_CLOUD_PATH")
            }

        case .ollamaStorage:
            result = ollamaStorageProof(entity: entity, verification: &verification, context: context, budgetMs: budgetMs, started: started)

        case .huggingFaceStorage:
            result = huggingFaceStorageProof(entity: entity, verification: &verification, budgetMs: budgetMs, started: started)
        }

        if result.runtimeMs > budgetMs, result.outcome != .verified {
            return VerificationStrategyResult(
                strategyID: result.strategyID,
                entityID: result.entityID,
                claim: result.claim,
                outcome: .unknown,
                runtimeMs: result.runtimeMs,
                budgetUsedMs: budgetMs,
                reasonCodes: result.reasonCodes + ["PROOF_BUDGET_EXCEEDED"],
                supportingEvidence: result.supportingEvidence,
                failedRequirements: result.failedRequirements,
                unknownRequirements: result.unknownRequirements + ["PROOF_BUDGET_EXCEEDED"]
            )
        }
        return result
    }

    static func primaryClaim(for strategy: VerificationStrategyID) -> VerificationClaimType {
        switch strategy {
        case .resolverSourceOfTruth: return .sourceOfTruth
        case .resolverRegenerability, .derivedData, .nodeModules: return .regenerability
        case .resolverActiveState, .claudeVMActive: return .activeState
        case .cursorMetadata, .workspaceRelationship: return .belongsToWorkspace
        case .fileProvider: return .remoteCopyExists
        case .ollamaStorage, .huggingFaceStorage: return .referenceGraph
        }
    }

    static func mapObservation(
        _ obs: ObservationRecord,
        strategy: VerificationStrategyID,
        entityID: String,
        claim: VerificationClaimType,
        started: Date
    ) -> VerificationStrategyResult {
        let outcome: VerificationStrategyOutcome
        switch obs.confidence {
        case .verified: outcome = .verified
        case .inferred: outcome = .inferred
        case .unknown: outcome = .unknown
        }
        return VerificationStrategyResult(
            strategyID: strategy,
            entityID: entityID,
            claim: claim,
            outcome: outcome,
            runtimeMs: msSince(started),
            budgetUsedMs: msSince(started),
            reasonCodes: [obs.reasonCode].compactMap { $0 },
            supportingEvidence: [obs.source.rawValue],
            failedRequirements: [],
            unknownRequirements: outcome == .verified ? [] : [obs.reasonCode ?? "UNKNOWN"]
        )
    }

    static func blockedResult(
        strategy: VerificationStrategyID,
        entityID: String,
        claim: VerificationClaimType,
        reason: String
    ) -> VerificationStrategyResult {
        VerificationStrategyResult(
            strategyID: strategy,
            entityID: entityID,
            claim: claim,
            outcome: .blocked,
            runtimeMs: 0,
            budgetUsedMs: 0,
            reasonCodes: [reason],
            supportingEvidence: [],
            failedRequirements: [],
            unknownRequirements: [reason]
        )
    }

    static func derivedDataProof(
        entity: DetectedEntity,
        evidence: inout EvidenceBundle,
        verification: inout VerificationAnnotation,
        started: Date
    ) -> VerificationStrategyResult {
        let sot = SourceOfTruthResolver.resolve(entity: entity.entity, annotation: entity.annotation, evidence: evidence)
        verification.sourceOfTruth = sot
        evidence.sourceOfTruth = sot.value
        let regen = RegenerabilityResolver.resolve(
            entity: entity.entity,
            annotation: entity.annotation,
            evidence: evidence,
            sourceOfTruth: sot
        )
        verification.regenerable = regen
        evidence.regenerable = regen.value
        let verified = sot.confidence == .verified || regen.confidence == .verified
        return VerificationStrategyResult(
            strategyID: .derivedData,
            entityID: entity.entity.id,
            claim: .regenerability,
            outcome: verified ? .verified : .unknown,
            runtimeMs: msSince(started),
            budgetUsedMs: msSince(started),
            reasonCodes: [sot.reasonCode, regen.reasonCode].compactMap { $0 },
            supportingEvidence: ["DERIVEDDATA_INFO_PLIST", "RELATIONSHIP_METADATA"],
            failedRequirements: [],
            unknownRequirements: verified ? [] : ["INCOMPLETE_DERIVEDDATA_CHAIN"]
        )
    }

    static func claudeActiveProof(
        entity: DetectedEntity,
        evidence: inout EvidenceBundle,
        verification: inout VerificationAnnotation,
        context: VerificationLoopContext,
        started: Date
    ) -> VerificationStrategyResult {
        let related = claudeRelatedPaths(entity: entity)
        let (active, conf, comp, reasons) = ActiveStateResolver.resolve(
            entityPath: entity.entity.path,
            associatedProcesses: entity.associatedProcesses,
            processes: context.processes,
            handles: context.handles,
            processCompleteness: context.processCompleteness,
            handleCompleteness: context.handleCompleteness,
            relatedPaths: related
        )
        verification.activeState = active
        verification.activeStateConfidence = conf
        verification.activeStateCompleteness = comp
        verification.unknownReasons.append(contentsOf: reasons)
        return VerificationStrategyResult(
            strategyID: .claudeVMActive,
            entityID: entity.entity.id,
            claim: .activeState,
            outcome: conf == .verified ? .verified : (conf == .inferred ? .inferred : .unknown),
            runtimeMs: msSince(started),
            budgetUsedMs: msSince(started),
            reasonCodes: reasons,
            supportingEvidence: ["EXACT_HANDLE_OR_CMDLINE"],
            failedRequirements: [],
            unknownRequirements: conf == .verified ? [] : reasons
        )
    }

    static func cursorRelationshipProof(entity: DetectedEntity, started: Date) -> VerificationStrategyResult {
        let rels = entity.annotation?.relationships ?? []
        let verified = rels.filter { $0.confidence == .verified && $0.type == .belongsToWorkspace }
        let conflict = rels.filter { $0.type == .belongsToWorkspace && $0.confidence == .verified }.count > 1
            && Set(rels.filter { $0.confidence == .verified && $0.type == .belongsToWorkspace }.map(\.target)).count > 1
        if conflict {
            return VerificationStrategyResult(
                strategyID: .cursorMetadata,
                entityID: entity.entity.id,
                claim: .belongsToWorkspace,
                outcome: .conflicted,
                runtimeMs: msSince(started),
                budgetUsedMs: msSince(started),
                reasonCodes: ["EVIDENCE_CONFLICT"],
                supportingEvidence: [],
                failedRequirements: ["single_workspace_target"],
                unknownRequirements: ["EVIDENCE_CONFLICT"]
            )
        }
        return VerificationStrategyResult(
            strategyID: .cursorMetadata,
            entityID: entity.entity.id,
            claim: .belongsToWorkspace,
            outcome: verified.isEmpty ? .unknown : .verified,
            runtimeMs: msSince(started),
            budgetUsedMs: msSince(started),
            reasonCodes: verified.isEmpty ? ["NO_EXPLICIT_METADATA"] : [],
            supportingEvidence: verified.map { "\($0.type.rawValue):\($0.target)" },
            failedRequirements: [],
            unknownRequirements: verified.isEmpty ? ["NO_EXPLICIT_METADATA"] : []
        )
    }

    static func claudeRelatedPaths(entity: DetectedEntity) -> [String] {
        guard entity.entity.id.contains("claude.vm") else { return [] }
        let p = entity.entity.path
        if p.hasSuffix(".bundle") || (entity.entity.id.contains(".bundle.") && !p.contains(".img") && !p.hasSuffix("vmlinuz") && !p.hasSuffix("machineIdentifier")) {
            return [p, "\(p)/rootfs.img", "\(p)/sessiondata.img", "\(p)/vmlinuz"]
        }
        return [p]
    }

    static func msSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    public static func isClaimAlreadyVerified(
        claim: VerificationClaimType,
        entity: DetectedEntity,
        verification: VerificationAnnotation
    ) -> Bool {
        switch claim {
        case .sourceOfTruth:
            return verification.sourceOfTruth.confidence == .verified
        case .regenerability:
            return verification.regenerable.confidence == .verified
        case .activeState:
            return verification.activeStateConfidence == .verified
        case .belongsToWorkspace:
            return (entity.annotation?.relationships ?? []).contains {
                $0.type == .belongsToWorkspace && $0.confidence == .verified && $0.presence == .present
            }
        case .derivedFrom:
            return (entity.annotation?.relationships ?? []).contains {
                ($0.type == .derivedFrom || $0.type == .belongsToWorkspace) && $0.confidence == .verified
            }
        case .provenance:
            return (entity.annotation?.provenance.confidence ?? .unknown) == .verified
        case .referenceGraph:
            return verification.referenceGraphConfidence == .verified
        case .reacquisition:
            return verification.reacquisition.confidence == .verified
        case .owningProduct, .sharedByteStatus, .belongsToVersion:
            return verification.vendorProofNotes.contains { $0.contains("VERIFIED") }
        default:
            return false
        }
    }

    static func ollamaStorageProof(
        entity: DetectedEntity,
        verification: inout VerificationAnnotation,
        context: VerificationLoopContext,
        budgetMs: Int,
        started: Date
    ) -> VerificationStrategyResult {
        let path = (entity.entity.path as NSString).standardizingPath
        let processNames = entity.associatedProcesses
        let inventory = VendorStorageProofIndex.inventory(forRoot: path)
            ?? OllamaStorageProofProvider(processNames: processNames).prove(rootPath: path, budgetMs: max(50, budgetMs))
        let match = inventory.entities.first { $0.entityID == entity.entity.id }
            ?? inventory.entities.first { path.hasPrefix(($0.canonicalPath as NSString).standardizingPath) || ($0.canonicalPath as NSString).standardizingPath.hasPrefix(path) }
            ?? inventory.entities.first { $0.entityKind == .modelsRoot }

        applyVendorEntity(match, to: &verification, vendorRule: "ollama.storage.proof.v1")
        let graphOK = match?.referenceGraphComplete == true
        let outcome: VerificationStrategyOutcome = graphOK ? .verified : .unknown
        return VerificationStrategyResult(
            strategyID: .ollamaStorage,
            entityID: entity.entity.id,
            claim: .referenceGraph,
            outcome: outcome,
            runtimeMs: msSince(started),
            budgetUsedMs: min(msSince(started), budgetMs),
            reasonCodes: match?.topBlockers ?? ["OLLAMA_PROOF_NO_MATCH"],
            supportingEvidence: [
                "OLLAMA_MANIFEST_INDEX",
                "BLOB_REVERSE_REFERENCES",
                "claimsVerified=\(inventory.claimsVerified)"
            ],
            failedRequirements: [],
            unknownRequirements: graphOK ? ["REACQUISITION_REMOTE_UNKNOWN"] : ["REFERENCE_GRAPH_INCOMPLETE", "REACQUISITION_REMOTE_UNKNOWN"]
        )
    }

    static func huggingFaceStorageProof(
        entity: DetectedEntity,
        verification: inout VerificationAnnotation,
        budgetMs: Int,
        started: Date
    ) -> VerificationStrategyResult {
        let path = (entity.entity.path as NSString).standardizingPath
        let inventory = VendorStorageProofIndex.inventory(forRoot: path)
            ?? HuggingFaceStorageProofProvider().prove(rootPath: path, budgetMs: max(50, budgetMs))
        let match = inventory.entities.first { $0.entityID == entity.entity.id }
            ?? inventory.entities.first { path.hasPrefix(($0.canonicalPath as NSString).standardizingPath) || ($0.canonicalPath as NSString).standardizingPath.hasPrefix(path) }
            ?? inventory.entities.first { $0.entityKind == .hubRoot }

        applyVendorEntity(match, to: &verification, vendorRule: "huggingface.storage.proof.v1")
        let graphOK = match?.referenceGraphComplete == true
        let outcome: VerificationStrategyOutcome = graphOK ? .verified : .unknown
        return VerificationStrategyResult(
            strategyID: .huggingFaceStorage,
            entityID: entity.entity.id,
            claim: .referenceGraph,
            outcome: outcome,
            runtimeMs: msSince(started),
            budgetUsedMs: min(msSince(started), budgetMs),
            reasonCodes: match?.topBlockers ?? ["HF_PROOF_NO_MATCH"],
            supportingEvidence: [
                "HF_HUB_REFS_SNAPSHOTS_BLOBS",
                "DISTINCT_BLOB_BYTE_ACCOUNTING",
                "claimsVerified=\(inventory.claimsVerified)"
            ],
            failedRequirements: [],
            unknownRequirements: graphOK ? ["REACQUISITION_REMOTE_UNKNOWN"] : ["REFERENCE_GRAPH_INCOMPLETE", "REACQUISITION_REMOTE_UNKNOWN"]
        )
    }

    static func applyVendorEntity(_ match: VendorSemanticEntity?, to verification: inout VerificationAnnotation, vendorRule: String) {
        guard let match else {
            verification.unknownReasons.append("VENDOR_PROOF_NO_MATCH")
            return
        }
        verification.vendorRuleID = vendorRule
        verification.logicalBytesProven = match.logicalBytes
        verification.uniqueBytesProven = match.uniqueBytes
        verification.sharedBytesProven = match.sharedBytes
        verification.referenceGraphConfidence = match.referenceGraphComplete ? .verified : .unknown
        verification.provenanceConfidence = match.provenanceConfidence
        verification.reacquisition = ObservationRecord(
            value: .unknown,
            confidence: match.reacquisitionConfidence,
            completeness: .partial,
            source: .filesystemMetadata,
            reasonCode: match.reacquisition.rawValue
        )
        // Do NOT set regenerable TRUE from local cache alone — remote reacquisition is unknown.
        if match.reacquisitionConfidence != .verified {
            verification.regenerable = ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .filesystemMetadata,
                reasonCode: "REACQUIRABLE_REMOTE_NOT_VERIFIED"
            )
        }
        if match.runtimeConfidence == .verified {
            verification.activeState = match.runtimeState
            verification.activeStateConfidence = .verified
        } else {
            verification.activeState = .unknown
            verification.activeStateConfidence = match.runtimeConfidence == .inferred ? .inferred : .unknown
            verification.unknownReasons.append("MODEL_ACTIVITY_NOT_PROVEN_FROM_SERVICE_ALONE")
        }
        var notes = match.notes
        notes.append("VENDOR_OWNED_VERIFIED")
        if match.referenceGraphComplete { notes.append("REFERENCE_GRAPH_VERIFIED") }
        if let u = match.uniqueBytes { notes.append("UNIQUE_BYTES=\(u)") }
        if let s = match.sharedBytes { notes.append("SHARED_BYTES=\(s)") }
        notes.append(contentsOf: match.topBlockers)
        verification.vendorProofNotes = notes
        verification.unknownReasons.append(contentsOf: match.topBlockers.filter { $0.contains("UNKNOWN") || $0.contains("INCOMPLETE") || $0.contains("SUSPECT") })
        verification.reconstructionMechanism = "VENDOR_NATIVE_CLEANUP_PREFERRED"
    }
}

public final class EvidenceResolutionCache: @unchecked Sendable {
    private var bundles: [String: EvidenceBundle] = [:]
    private var openHandleCache: [String: PredicateValue] = [:]
    private var verifications: [String: VerificationAnnotation] = [:]
    private let lock = NSLock()

    public init() {}

    public func evidence(
        for path: String,
        entity: DetectedEntity,
        resolver: EvidenceResolver
    ) -> EvidenceBundle {
        let key = (PathGlob.expandHome(path) as NSString).standardizingPath
        lock.lock()
        if let hit = bundles[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let bundle = resolver.resolve(path: path, associatedProcesses: entity.associatedProcesses)
        lock.lock()
        bundles[key] = bundle
        lock.unlock()
        return bundle
    }

    public func storeEvidence(path: String, bundle: EvidenceBundle) {
        let key = (PathGlob.expandHome(path) as NSString).standardizingPath
        lock.lock()
        bundles[key] = bundle
        lock.unlock()
    }

    public func verification(for entityID: String) -> VerificationAnnotation? {
        lock.lock()
        let hit = verifications[entityID]
        lock.unlock()
        return hit
    }

    public func storeVerification(entityID: String, verification: VerificationAnnotation) {
        lock.lock()
        verifications[entityID] = verification
        lock.unlock()
    }

    public func openHandle(path: String, handles: any OpenHandleChecker) -> PredicateValue {
        let key = (PathGlob.expandHome(path) as NSString).standardizingPath
        lock.lock()
        if let hit = openHandleCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let v = handles.hasOpenHandles(path: path)
        lock.lock()
        openHandleCache[key] = v
        lock.unlock()
        return v
    }
}
