import Foundation

public enum StrictProofRootCause: String, Codable, Sendable {
    case realEvidenceIncomplete = "REAL_EVIDENCE_INCOMPLETE"
    case rootChildBlockerScopeBug = "ROOT_CHILD_BLOCKER_SCOPE_BUG"
    case claimTransportBug = "CLAIM_TRANSPORT_BUG"
    case relationshipTypeContractMismatch = "RELATIONSHIP_TYPE_CONTRACT_MISMATCH"
    case claimPrecedenceBug = "CLAIM_PRECEDENCE_BUG"
    case sourcePathStale = "SOURCE_PATH_STALE"
    case sourceMissing = "SOURCE_MISSING"
    case sotResolverBug = "SOT_RESOLVER_BUG"
    case regenDependencyBug = "REGEN_DEPENDENCY_BUG"
    case reportingAggregationOnly = "REPORTING_AGGREGATION_ONLY"
    case other = "OTHER"
}

public enum ContradictionClassification: String, Codable, Sendable {
    case expectedAggregation = "EXPECTED_AGGREGATION"
    case blockerScopeBug = "BLOCKER_SCOPE_BUG"
    case claimTransportBug = "CLAIM_TRANSPORT_BUG"
    case contractMismatch = "CONTRACT_MISMATCH"
    case evidenceStateChange = "EVIDENCE_STATE_CHANGE"
    case other = "OTHER"
}

public struct StrictProofRequirement: Codable, Sendable, Equatable {
    public var requirement: String
    public var required: Bool
    public var value: String?
    public var confidence: String?
    public var completeness: String?
    public var evidenceSource: String?
    public var satisfied: Bool
    public var blockingReason: String?
}

public struct ClaimTransportLayer: Codable, Sendable, Equatable {
    public var layer: String
    public var relationshipTypes: [String]
    public var verifiedRelationshipCount: Int
    public var sourceOfTruth: String?
    public var sourceOfTruthConfidence: String?
    public var regenerability: String?
    public var regenerabilityConfidence: String?
    public var claimSurvived: Bool
}

public struct DerivedDataStrictProofEntity: Codable, Sendable, Equatable {
    public var entityID: String
    public var path: String
    public var isRootEntity: Bool
    public var isConcreteChild: Bool
    public var isSkipChild: Bool
    public var workspacePath: String?
    public var workspacePathPresent: Bool
    public var workspaceRelationshipType: String?
    public var workspaceRelationshipConfidence: String?
    public var workspaceRelationshipPresence: String?
    public var sourceExists: Bool?
    public var generatedBy: String?
    public var derivedFrom: String?
    public var sourceOfTruth: String?
    public var sourceOfTruthConfidence: String?
    public var regenerability: String?
    public var regenerabilityConfidence: String?
    public var activeState: String?
    public var activeStateConfidence: String?
    public var openFileState: String?
    public var openFileConfidence: String?
    public var evidenceCompleteness: String?
    public var evidenceFreshness: String?
    public var evidenceConflicts: Bool
    public var sotResolverInputRelationshipCount: Int
    public var sotResolverInputVerifiedCount: Int
    public var sotResolverOutput: String?
    public var sotResolverReasonCode: String?
    public var regenResolverOutput: String?
    public var regenResolverReasonCode: String?
    public var firstSOTBlocker: String?
    public var firstRegenBlocker: String?
    public var regenBlockedBySOT: Bool
    public var strictRequirements: [StrictProofRequirement]
    public var firstUnsatisfiedRequirement: String?
    public var causalBlockerChain: [String]
    public var moveToTrashSafety: String?
    public var moveToTrashEligible: Bool?
    public var recommendation: String?
    public var recommendationDisposition: String?
    public var preflightAllowed: Bool?
    public var mutationReadiness: String?
    public var primaryRootCause: String
    public var rootCauseExplanation: String
    public var claimTransport: [ClaimTransportLayer]
}

public struct DerivedDataStrictProofChainReport: Codable, Sendable, Equatable {
    public var phase: String
    public var rootDerivedDataEntities: Int
    public var concreteDerivedDataEntities: Int
    public var skipChildEntities: Int
    public var rootWorkspaceRelationshipVerified: Int
    public var childWorkspaceRelationshipVerified: Int
    public var rootSOTFalseVerified: Int
    public var childSOTFalseVerified: Int
    public var rootRegenTrueVerified: Int
    public var childRegenTrueVerified: Int
    public var contradictionClassification: String
    public var contradictionExplanation: String
    public var rootChildContaminationSuspected: Bool
    public var claimTransportBugSuspected: Bool
    public var claimPrecedenceBugSuspected: Bool
    public var relationshipContractMismatchSuspected: Bool
    public var reportingAggregationOnly: Bool
    public var primaryRootCauseCategory: String
    public var architecturalFixMade: Bool
    public var entities: [DerivedDataStrictProofEntity]
    public var exactRealChildEntityIDs: [String]
    public var firstRealMutationGateStatus: String
    public var selectedCandidate: String?
    public var approvalRequired: Int
    public var remainingExactBlocker: String?
}

public enum DerivedDataStrictProofChainAnalyzer {
    public static let skipChildNames: Set<String> = DerivedDataSurfaceAnalyzer.skipChildNames

    public static func analyze(
        items: [ClassifiedItem],
        snapshotsByEntityID: [String: EntitySafetySnapshot],
        decisionCatalog: ActionDecisionCatalog,
        recommendations: [ActionRecommendationResult],
        preflights: [ActionPreflightResult],
        mutationGate: MutationGateReport,
        readiness: DerivedDataMutationReadinessReport,
        gate: FirstRealMutationGateReport
    ) -> DerivedDataStrictProofChainReport {
        var recMap: [String: ActionRecommendationResult] = [:]
        for r in recommendations { recMap[r.entityID] = r }
        var preMap: [String: ActionPreflightResult] = [:]
        for p in preflights where p.action == .moveToTrash { preMap[p.entityID] = p }
        var gateMap: [String: MutationGateResult] = [:]
        for e in mutationGate.entries { gateMap["\(e.entityID):\(e.action)"] = e }
        let readinessByID = Dictionary(uniqueKeysWithValues: readiness.entries.map { ($0.entityID, $0) })

        let derivedItems = items.filter {
            ActionPolicy.isDerivedData($0) || DerivedDataMutationReadinessAnalyzer.isDerivedDataEntity($0)
        }.sorted { $0.detected.entity.id < $1.detected.entity.id }

        var entities: [DerivedDataStrictProofEntity] = []
        var rootCount = 0, concreteCount = 0, skipCount = 0
        var rootWsVerified = 0, childWsVerified = 0
        var rootSOT = 0, childSOT = 0, rootRegen = 0, childRegen = 0
        var exactChildIDs: [String] = []

        for item in derivedItems {
            let classification = classifyEntity(item)
            switch classification.kind {
            case .root: rootCount += 1
            case .concreteChild: concreteCount += 1
            case .skipChild: skipCount += 1
            }
            if classification.kind == .concreteChild { exactChildIDs.append(item.detected.entity.id) }

            let entity = buildEntityReport(
                item: item,
                classification: classification,
                snapshot: snapshotsByEntityID[item.detected.entity.id],
                readiness: readinessByID[item.detected.entity.id],
                trashDecision: decisionCatalog.set(for: item.detected.entity.id)?.decision(for: .moveToTrash),
                recommendation: recMap[item.detected.entity.id],
                preflight: preMap[item.detected.entity.id],
                gateResult: gateMap["\(item.detected.entity.id):\(StorageAction.moveToTrash.rawValue)"]
            )
            entities.append(entity)

            let wsVerified = entity.workspaceRelationshipConfidence == EvidenceConfidence.verified.rawValue
                && entity.workspaceRelationshipPresence == RelationshipPresence.present.rawValue
            let sotVerified = entity.sourceOfTruth == PredicateValue.false.rawValue
                && entity.sourceOfTruthConfidence == EvidenceConfidence.verified.rawValue
            let regenVerified = entity.regenerability == PredicateValue.true.rawValue
                && entity.regenerabilityConfidence == EvidenceConfidence.verified.rawValue

            switch classification.kind {
            case .root:
                if wsVerified { rootWsVerified += 1 }
                if sotVerified { rootSOT += 1 }
                if regenVerified { rootRegen += 1 }
            case .concreteChild:
                if wsVerified { childWsVerified += 1 }
                if sotVerified { childSOT += 1 }
                if regenVerified { childRegen += 1 }
            case .skipChild:
                break
            }
        }

        let contradiction = reconcileContradiction(entities: entities)
        let primary = classifyPrimaryRootCause(entities: entities, contradiction: contradiction)

        let proofChild = entities.first {
            $0.isConcreteChild && !$0.isSkipChild
                && $0.workspaceRelationshipConfidence == EvidenceConfidence.verified.rawValue
        }
        let remainingBlocker = proofChild?.firstUnsatisfiedRequirement
            ?? proofChild?.causalBlockerChain.first
            ?? entities.first(where: { $0.isConcreteChild })?.firstUnsatisfiedRequirement

        return DerivedDataStrictProofChainReport(
            phase: "P2.0.5",
            rootDerivedDataEntities: rootCount,
            concreteDerivedDataEntities: concreteCount,
            skipChildEntities: skipCount,
            rootWorkspaceRelationshipVerified: rootWsVerified,
            childWorkspaceRelationshipVerified: childWsVerified,
            rootSOTFalseVerified: rootSOT,
            childSOTFalseVerified: childSOT,
            rootRegenTrueVerified: rootRegen,
            childRegenTrueVerified: childRegen,
            contradictionClassification: contradiction.classification.rawValue,
            contradictionExplanation: contradiction.explanation,
            rootChildContaminationSuspected: contradiction.rootChildContamination,
            claimTransportBugSuspected: contradiction.claimTransportBug,
            claimPrecedenceBugSuspected: contradiction.claimPrecedenceBug,
            relationshipContractMismatchSuspected: contradiction.contractMismatch,
            reportingAggregationOnly: contradiction.reportingOnly,
            primaryRootCauseCategory: primary.rawValue,
            architecturalFixMade: false,
            entities: entities,
            exactRealChildEntityIDs: exactChildIDs.sorted(),
            firstRealMutationGateStatus: gate.status,
            selectedCandidate: gate.selectedCandidate,
            approvalRequired: gate.approvalRequired,
            remainingExactBlocker: remainingBlocker
        )
    }

    enum EntityKind { case root, concreteChild, skipChild }

    struct EntityClassification {
        var kind: EntityKind
        var isRootEntity: Bool
        var isConcreteChild: Bool
        var isSkipChild: Bool
    }

    static func classifyEntity(_ item: ClassifiedItem) -> EntityClassification {
        let path = (item.detected.entity.path as NSString).standardizingPath
        let name = (path as NSString).lastPathComponent
        let isRoot = item.detected.entity.id == "xcode.derived_data"
            || path.lowercased().hasSuffix("/deriveddata")
        let isSkip = skipChildNames.contains(name)
            || item.detected.entity.id == "xcode.module_cache"
            || item.detected.entity.id == "xcode.source_packages"
        let isConcrete = DerivedDataSurfaceAnalyzer.isConcreteDerivedDataChild(item) && !isRoot && !isSkip
        let kind: EntityKind
        if isRoot { kind = .root }
        else if isSkip { kind = .skipChild }
        else if isConcrete { kind = .concreteChild }
        else { kind = .skipChild }
        return EntityClassification(kind: kind, isRootEntity: isRoot, isConcreteChild: isConcrete, isSkipChild: isSkip && !isConcrete)
    }

    static func buildEntityReport(
        item: ClassifiedItem,
        classification: EntityClassification,
        snapshot: EntitySafetySnapshot?,
        readiness: DerivedDataMutationReadinessEntry?,
        trashDecision: ActionDecision?,
        recommendation: ActionRecommendationResult?,
        preflight: ActionPreflightResult?,
        gateResult: MutationGateResult?
    ) -> DerivedDataStrictProofEntity {
        let rel = verifiedWorkspaceRelationship(item: item, snapshot: snapshot)
        let wsPath = rel?.target ?? readiness?.sourceWorkspace
        let wsPresent = wsPath != nil
            || FileManager.default.fileExists(atPath: "\(item.detected.entity.path)/info.plist")
        let sourceExists = rel.map { $0.presence == .present }
            ?? readiness?.sourceWorkspaceExists
            ?? wsPath.map { FileManager.default.fileExists(atPath: $0) }

        let v = snapshot?.verification ?? item.verification
        let preds = snapshot?.predicates
        let sot = preds?.sourceOfTruth ?? v?.sourceOfTruth
        let regen = preds?.regenerability ?? v?.regenerable

        let detectorRels = item.detected.annotation?.relationships ?? []
        let verifiedRels = detectorRels.filter { $0.confidence == .verified }
        let resolverSOT = SourceOfTruthResolver.resolve(
            entity: item.detected.entity,
            annotation: item.detected.annotation,
            evidence: snapshot?.evidence ?? EvidenceBundle(canonicalPath: item.detected.entity.path)
        )
        let resolverRegen = RegenerabilityResolver.resolve(
            entity: item.detected.entity,
            annotation: item.detected.annotation,
            evidence: snapshot?.evidence ?? EvidenceBundle(canonicalPath: item.detected.entity.path),
            sourceOfTruth: sot ?? resolverSOT
        )

        let requirements = buildStrictRequirements(
            item: item,
            classification: classification,
            rel: rel,
            sourceExists: sourceExists,
            sot: sot,
            regen: regen,
            snapshot: snapshot,
            readiness: readiness,
            trashDecision: trashDecision
        )
        let firstUnsat = requirements.first(where: { $0.required && !$0.satisfied })?.requirement
        let causal = buildCausalChain(
            requirements: requirements,
            trashDecision: trashDecision,
            readiness: readiness,
            sot: sot,
            regen: regen
        )
        let (firstSOT, firstRegen, regenBlockedBySOT) = sotRegenBlockers(
            requirements: requirements,
            sot: sot,
            regen: regen
        )
        let transport = buildClaimTransport(
            item: item,
            snapshot: snapshot,
            sot: sot,
            regen: regen,
            resolverSOT: resolverSOT,
            resolverRegen: resolverRegen
        )
        let primary = entityPrimaryCause(
            classification: classification,
            requirements: requirements,
            causal: causal,
            sot: sot,
            regen: regen,
            transport: transport
        )

        return DerivedDataStrictProofEntity(
            entityID: item.detected.entity.id,
            path: snapshot?.evidence.canonicalPath ?? item.detected.entity.path,
            isRootEntity: classification.isRootEntity,
            isConcreteChild: classification.isConcreteChild,
            isSkipChild: classification.isSkipChild,
            workspacePath: wsPath,
            workspacePathPresent: wsPresent,
            workspaceRelationshipType: rel?.type.rawValue,
            workspaceRelationshipConfidence: rel?.confidence.rawValue,
            workspaceRelationshipPresence: rel?.presence.rawValue,
            sourceExists: sourceExists,
            generatedBy: item.detected.annotation?.provenance.generatedByProduct?.name
                ?? (item.detected.annotation?.lifecycle.role == .generatedArtifact ? "XCODE" : item.detected.entity.subcategory),
            derivedFrom: rel?.target ?? readiness?.derivedFrom,
            sourceOfTruth: sot?.value.rawValue,
            sourceOfTruthConfidence: sot?.confidence.rawValue,
            regenerability: regen?.value.rawValue,
            regenerabilityConfidence: regen?.confidence.rawValue,
            activeState: preds?.activeState.rawValue ?? v?.activeState.rawValue,
            activeStateConfidence: preds?.activeStateConfidence.rawValue ?? v?.activeStateConfidence.rawValue,
            openFileState: preds?.openFileHandle.rawValue ?? snapshot?.evidence.openFileHandle.rawValue,
            openFileConfidence: preds?.openFileConfidence.rawValue,
            evidenceCompleteness: readiness?.evidenceCompleteness ?? v?.activeStateCompleteness.rawValue,
            evidenceFreshness: readiness?.evidenceFreshness,
            evidenceConflicts: preds?.hasEvidenceConflict ?? false,
            sotResolverInputRelationshipCount: detectorRels.count,
            sotResolverInputVerifiedCount: verifiedRels.count,
            sotResolverOutput: sot?.value.rawValue ?? resolverSOT.value.rawValue,
            sotResolverReasonCode: sot?.reasonCode ?? resolverSOT.reasonCode,
            regenResolverOutput: regen?.value.rawValue ?? resolverRegen.value.rawValue,
            regenResolverReasonCode: regen?.reasonCode ?? resolverRegen.reasonCode,
            firstSOTBlocker: firstSOT,
            firstRegenBlocker: firstRegen,
            regenBlockedBySOT: regenBlockedBySOT,
            strictRequirements: requirements,
            firstUnsatisfiedRequirement: firstUnsat,
            causalBlockerChain: causal,
            moveToTrashSafety: trashDecision?.safetyClass.rawValue,
            moveToTrashEligible: trashDecision?.eligible,
            recommendation: recommendation?.recommendedAction.rawValue,
            recommendationDisposition: dispositionLabel(recommendation?.disposition),
            preflightAllowed: preflight?.allowed,
            mutationReadiness: gateResult?.readiness ?? readiness?.mutationReadiness,
            primaryRootCause: primary.rawValue,
            rootCauseExplanation: primaryExplanation(primary, classification: classification, firstUnsat: firstUnsat),
            claimTransport: transport
        )
    }

    static func verifiedWorkspaceRelationship(item: ClassifiedItem, snapshot: EntitySafetySnapshot?) -> EntityRelationship? {
        let rels = item.detected.annotation?.relationships ?? []
        if let hit = rels.first(where: {
            ($0.type == .derivedFrom || $0.type == .belongsToWorkspace) && $0.confidence == .verified
        }) {
            return hit
        }
        return snapshot?.relationships.first {
            ($0.type == .derivedFrom || $0.type == .belongsToWorkspace) && $0.confidence == .verified
        }
    }

    static func buildStrictRequirements(
        item: ClassifiedItem,
        classification: EntityClassification,
        rel: EntityRelationship?,
        sourceExists: Bool?,
        sot: ObservationRecord?,
        regen: ObservationRecord?,
        snapshot: EntitySafetySnapshot?,
        readiness: DerivedDataMutationReadinessEntry?,
        trashDecision: ActionDecision?
    ) -> [StrictProofRequirement] {
        func req(_ name: String, _ required: Bool, _ ok: Bool, _ value: String? = nil, _ conf: String? = nil, _ source: String? = nil, _ block: String? = nil) -> StrictProofRequirement {
            StrictProofRequirement(
                requirement: name,
                required: required,
                value: value,
                confidence: conf,
                completeness: readiness?.evidenceCompleteness,
                evidenceSource: source,
                satisfied: ok,
                blockingReason: ok ? nil : block
            )
        }

        let wsVerified = rel?.confidence == .verified && rel?.presence == .present
        let sotOK = sot?.value == .false && sot?.confidence == .verified
        let regenOK = regen?.value == .true && regen?.confidence == .verified
        let xcodeInactive = readiness?.xcodeRunning == "inactive"
        let openSafe = readiness?.openFileState == "false" && readiness?.openFileConfidence == "verified"
            || snapshot?.predicates.openFileHandle == .false
        let activeInactive = readiness?.activeState != "ACTIVE"
            || readiness?.activeStateConfidence != "VERIFIED"

        var list: [StrictProofRequirement] = [
            req("entity_identity_verified", true, !item.detected.entity.id.isEmpty, item.detected.entity.id, nil, "Detector"),
            req("generated_by_xcode_verified", true,
                item.detected.annotation?.semanticType == "XCODE_DERIVEDDATA_INSTANCE"
                    || item.detected.annotation?.lifecycle.role == .generatedArtifact,
                item.detected.annotation?.semanticType, nil, "Detector/Lifecycle",
                "GENERATED_BY_NOT_VERIFIED"),
            req("explicit_workspace_relationship_verified", !classification.isRootEntity,
                wsVerified == true, rel?.target, rel?.confidence.rawValue, "Detector metadata",
                "MISSING_EXPLICIT_WORKSPACE_RELATIONSHIP"),
            req("source_workspace_exists_verified", !classification.isRootEntity && wsVerified == true,
                sourceExists == true, rel?.target, rel?.presence.rawValue, "Filesystem",
                sourceExists == false ? "SOURCE_WORKSPACE_MISSING" : "SOURCE_EXISTS_UNKNOWN"),
            req("sot_false_verified", !classification.isRootEntity,
                sotOK, sot?.value.rawValue, sot?.confidence.rawValue, "SourceOfTruthResolver/Snapshot",
                sot?.confidence == .verified ? nil : "SOT_PROOF_INCOMPLETE"),
            req("regenerable_true_verified", !classification.isRootEntity,
                regenOK, regen?.value.rawValue, regen?.confidence.rawValue, "RegenerabilityResolver/Snapshot",
                !sotOK ? "REGEN_BLOCKED_BY_SOT" : "REGEN_PROOF_INCOMPLETE"),
            req("runtime_xcode_inactive", !classification.isRootEntity && sotOK == true && regenOK == true,
                xcodeInactive == true, readiness?.xcodeRunning, nil, "RuntimeObservationIndex",
                "RUNTIME_ACTIVE_BLOCK"),
            req("open_file_safe_verified", !classification.isRootEntity && sotOK == true && regenOK == true,
                openSafe, readiness?.openFileState, readiness?.openFileConfidence, "RuntimeObservationIndex",
                "OPEN_STATE_INCOMPLETE"),
            req("source_inactive_verified", !classification.isRootEntity && sotOK == true && regenOK == true,
                activeInactive, readiness?.activeState, readiness?.activeStateConfidence, "ActiveStateResolver",
                "SOURCE_ACTIVE"),
            req("move_to_trash_safety_green", !classification.isRootEntity,
                trashDecision?.safetyClass == .green && trashDecision?.eligible == true,
                trashDecision?.safetyClass.rawValue, nil, "ActionDecisionSet",
                trashDecision?.blockedReasons.first?.rawValue ?? "MOVE_TO_TRASH_NOT_GREEN"),
        ]
        return list
    }

    static func buildCausalChain(
        requirements: [StrictProofRequirement],
        trashDecision: ActionDecision?,
        readiness: DerivedDataMutationReadinessEntry?,
        sot: ObservationRecord?,
        regen: ObservationRecord?
    ) -> [String] {
        var chain: [String] = []
        for r in requirements where r.required && !r.satisfied {
            if let block = r.blockingReason { chain.append(block) }
            else { chain.append(r.requirement) }
        }
        if trashDecision?.safetyClass == .red {
            for reason in trashDecision?.blockedReasons ?? [] {
                if !chain.contains(reason.rawValue) { chain.append(reason.rawValue) }
            }
        }
        if chain.isEmpty, readiness?.mutationReadiness == MutationReadiness.preflightRequired.rawValue {
            chain.append("PREFLIGHT_REQUIRED")
        }
        if chain.isEmpty, sot?.value == .false, sot?.confidence == .verified,
           regen?.value == .true, regen?.confidence == .verified {
            chain.append("STATIC_PROOF_COMPLETE_RUNTIME_OR_APPROVAL_PENDING")
        }
        return chain
    }

    static func sotRegenBlockers(
        requirements: [StrictProofRequirement],
        sot: ObservationRecord?,
        regen: ObservationRecord?
    ) -> (firstSOT: String?, firstRegen: String?, blockedBySOT: Bool) {
        let sotReq = requirements.first { $0.requirement == "sot_false_verified" }
        let regenReq = requirements.first { $0.requirement == "regenerable_true_verified" }
        let sotOK = sot?.value == .false && sot?.confidence == .verified
        let blockedBySOT = !sotOK
        return (sotReq?.blockingReason ?? sotReq?.requirement, regenReq?.blockingReason ?? regenReq?.requirement, blockedBySOT)
    }

    static func buildClaimTransport(
        item: ClassifiedItem,
        snapshot: EntitySafetySnapshot?,
        sot: ObservationRecord?,
        regen: ObservationRecord?,
        resolverSOT: ObservationRecord,
        resolverRegen: ObservationRecord
    ) -> [ClaimTransportLayer] {
        let detectorRels = item.detected.annotation?.relationships ?? []
        let detectorVerified = detectorRels.filter { $0.confidence == .verified }.map(\.type.rawValue)
        let itemSOT = item.verification?.sourceOfTruth
        let itemRegen = item.verification?.regenerable

        return [
            ClaimTransportLayer(
                layer: "DetectorMetadata",
                relationshipTypes: detectorRels.map(\.type.rawValue),
                verifiedRelationshipCount: detectorRels.filter { $0.confidence == .verified }.count,
                sourceOfTruth: nil,
                sourceOfTruthConfidence: nil,
                regenerability: nil,
                regenerabilityConfidence: nil,
                claimSurvived: !detectorVerified.isEmpty
            ),
            ClaimTransportLayer(
                layer: "VerificationAnnotation",
                relationshipTypes: detectorVerified,
                verifiedRelationshipCount: detectorVerified.count,
                sourceOfTruth: itemSOT?.value.rawValue,
                sourceOfTruthConfidence: itemSOT?.confidence.rawValue,
                regenerability: itemRegen?.value.rawValue,
                regenerabilityConfidence: itemRegen?.confidence.rawValue,
                claimSurvived: itemSOT?.confidence == .verified || itemRegen?.confidence == .verified
            ),
            ClaimTransportLayer(
                layer: "EntitySafetySnapshot",
                relationshipTypes: detectorVerified,
                verifiedRelationshipCount: detectorVerified.count,
                sourceOfTruth: sot?.value.rawValue,
                sourceOfTruthConfidence: sot?.confidence.rawValue,
                regenerability: regen?.value.rawValue,
                regenerabilityConfidence: regen?.confidence.rawValue,
                claimSurvived: sot?.confidence == .verified && regen?.confidence == .verified
            ),
            ClaimTransportLayer(
                layer: "ResolverDirect",
                relationshipTypes: detectorVerified,
                verifiedRelationshipCount: detectorVerified.count,
                sourceOfTruth: resolverSOT.value.rawValue,
                sourceOfTruthConfidence: resolverSOT.confidence.rawValue,
                regenerability: resolverRegen.value.rawValue,
                regenerabilityConfidence: resolverRegen.confidence.rawValue,
                claimSurvived: resolverSOT.confidence == .verified && resolverRegen.confidence == .verified
            ),
        ]
    }

    static func entityPrimaryCause(
        classification: EntityClassification,
        requirements: [StrictProofRequirement],
        causal: [String],
        sot: ObservationRecord?,
        regen: ObservationRecord?,
        transport: [ClaimTransportLayer]
    ) -> StrictProofRootCause {
        if classification.isRootEntity {
            return .realEvidenceIncomplete
        }
        if classification.isSkipChild {
            return .realEvidenceIncomplete
        }
        let sotOK = sot?.value == .false && sot?.confidence == .verified
        let regenOK = regen?.value == .true && regen?.confidence == .verified
        if sotOK && regenOK {
            if causal.contains("RUNTIME_ACTIVE_BLOCK") || causal.contains("SOURCE_ACTIVE") || causal.contains("OPEN_STATE_INCOMPLETE") || causal.contains("SOURCE_OPEN") {
                return .realEvidenceIncomplete
            }
            if causal.contains("MOVE_TO_TRASH_NOT_GREEN") || causal.contains(where: { $0.contains("SAFETY") }) {
                return .realEvidenceIncomplete
            }
        }
        if transport.first?.claimSurvived == true,
           transport.last(where: { $0.layer == "EntitySafetySnapshot" })?.claimSurvived == false {
            return .claimTransportBug
        }
        if causal.contains("MISSING_EXPLICIT_WORKSPACE_RELATIONSHIP") {
            return requirements.first(where: { $0.requirement == "explicit_workspace_relationship_verified" })?.satisfied == false
                ? .realEvidenceIncomplete : .other
        }
        if causal.contains("SOURCE_WORKSPACE_MISSING") { return .sourceMissing }
        if causal.contains("SOT_PROOF_INCOMPLETE") { return .realEvidenceIncomplete }
        return .realEvidenceIncomplete
    }

    static func primaryExplanation(_ cause: StrictProofRootCause, classification: EntityClassification, firstUnsat: String?) -> String {
        switch cause {
        case .realEvidenceIncomplete:
            if classification.isRootEntity {
                return "Aggregate DerivedData root lacks per-project workspace metadata — expected UNKNOWN at root."
            }
            return "Strict proof chain incomplete at: \(firstUnsat ?? "unknown") — believe real evidence."
        case .claimTransportBug:
            return "VERIFIED relationship or SOT/regen claim lost between detector and snapshot."
        default:
            return cause.rawValue
        }
    }

    static func reconcileContradiction(entities: [DerivedDataStrictProofEntity]) -> (
        classification: ContradictionClassification,
        explanation: String,
        rootChildContamination: Bool,
        claimTransportBug: Bool,
        claimPrecedenceBug: Bool,
        contractMismatch: Bool,
        reportingOnly: Bool
    ) {
        let childWithWs = entities.filter { $0.isConcreteChild && $0.workspaceRelationshipConfidence == EvidenceConfidence.verified.rawValue }
        let childMissingWs = entities.filter { $0.isConcreteChild && $0.workspaceRelationshipConfidence != EvidenceConfidence.verified.rawValue }
        let rootMissingWs = entities.filter { $0.isRootEntity && $0.workspaceRelationshipConfidence != EvidenceConfidence.verified.rawValue }

        if !childWithWs.isEmpty && !childMissingWs.isEmpty {
            return (
                .expectedAggregation,
                "Different entities: \(childWithWs.map(\.entityID).joined(separator: ", ")) have VERIFIED workspace relation; \(childMissingWs.map(\.entityID).joined(separator: ", ")) lack explicit WorkspacePath. Aggregate MISSING_EXPLICIT_WORKSPACE_RELATIONSHIP is not a single-entity contradiction.",
                false, false, false, false, true
            )
        }
        if !childWithWs.isEmpty, childWithWs.allSatisfy({ $0.childSOTVerified }) {
            return (
                .expectedAggregation,
                "Concrete child(ren) reach SOT FALSE VERIFIED + regen TRUE VERIFIED. Remaining gate blockers are runtime/approval layer, not missing workspace relationship.",
                false, false, false, false, true
            )
        }
        if !rootMissingWs.isEmpty && !childWithWs.isEmpty {
            return (
                .expectedAggregation,
                "Root entity workspace UNKNOWN does not contaminate child with VERIFIED explicit relationship.",
                false, false, false, false, true
            )
        }
        return (.other, "No aggregate contradiction pattern matched.", false, false, false, false, false)
    }

    static func classifyPrimaryRootCause(
        entities: [DerivedDataStrictProofEntity],
        contradiction: (classification: ContradictionClassification, explanation: String, rootChildContamination: Bool, claimTransportBug: Bool, claimPrecedenceBug: Bool, contractMismatch: Bool, reportingOnly: Bool)
    ) -> StrictProofRootCause {
        if contradiction.claimTransportBug { return .claimTransportBug }
        if contradiction.rootChildContamination { return .rootChildBlockerScopeBug }
        if contradiction.reportingOnly && contradiction.classification == .expectedAggregation { return .reportingAggregationOnly }

        let proofChild = entities.first {
            $0.isConcreteChild && !$0.isSkipChild
                && $0.workspaceRelationshipConfidence == EvidenceConfidence.verified.rawValue
        }
        if let proofChild {
            if proofChild.sourceOfTruth == PredicateValue.false.rawValue,
               proofChild.sourceOfTruthConfidence == EvidenceConfidence.verified.rawValue,
               proofChild.regenerability == PredicateValue.true.rawValue,
               proofChild.regenerabilityConfidence == EvidenceConfidence.verified.rawValue {
                return .realEvidenceIncomplete
            }
            return StrictProofRootCause(rawValue: proofChild.primaryRootCause) ?? .realEvidenceIncomplete
        }
        return .realEvidenceIncomplete
    }

    static func dispositionLabel(_ disposition: RecommendationDisposition?) -> String? {
        guard let disposition else { return nil }
        switch disposition {
        case .actionable(let a): return "actionable:\(a.rawValue)"
        case .keep: return "keep"
        case .verifyMore(let c): return "verifyMore:\(c.map(\.rawValue).joined(separator: ","))"
        }
    }
}

private extension DerivedDataStrictProofEntity {
    var childSOTVerified: Bool {
        sourceOfTruth == PredicateValue.false.rawValue && sourceOfTruthConfidence == EvidenceConfidence.verified.rawValue
    }
}
