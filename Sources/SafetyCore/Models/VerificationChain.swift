import Foundation

public struct VerificationChain: Codable, Sendable, Equatable {
    public var chainID: String
    public var entityID: String
    public var claim: String
    public var result: String
    public var confidence: EvidenceConfidence
    public var supportingEvidenceIDs: [String]
    public var relationshipIDs: [String]
    public var vendorRuleID: String?
    public var requiredSteps: [String]
    public var satisfiedRequirements: [String]
    public var failedRequirements: [String]
    public var unknownRequirements: [String]
    public var verifiedStepCount: Int
    public var inferredStepCount: Int
    public var unknownStepCount: Int
    public var failureReason: String?

    public init(
        chainID: String = UUID().uuidString,
        entityID: String,
        claim: String,
        result: String,
        confidence: EvidenceConfidence,
        supportingEvidenceIDs: [String] = [],
        relationshipIDs: [String] = [],
        vendorRuleID: String? = nil,
        requiredSteps: [String] = [],
        satisfiedRequirements: [String] = [],
        failedRequirements: [String] = [],
        unknownRequirements: [String] = [],
        failureReason: String? = nil
    ) {
        self.chainID = chainID
        self.entityID = entityID
        self.claim = claim
        self.result = result
        self.confidence = confidence
        self.supportingEvidenceIDs = supportingEvidenceIDs
        self.relationshipIDs = relationshipIDs
        self.vendorRuleID = vendorRuleID
        self.requiredSteps = requiredSteps
        self.satisfiedRequirements = satisfiedRequirements
        self.failedRequirements = failedRequirements
        self.unknownRequirements = unknownRequirements
        self.verifiedStepCount = satisfiedRequirements.count
        self.inferredStepCount = confidence == .inferred ? 1 : 0
        self.unknownStepCount = unknownRequirements.count
        self.failureReason = failureReason
    }

    /// Strict VERIFIED only when confidence is VERIFIED, no failed/unknown required steps.
    public var satisfiesStrictChain: Bool {
        confidence == .verified
            && failedRequirements.isEmpty
            && unknownRequirements.isEmpty
            && (requiredSteps.isEmpty || Set(requiredSteps).isSubset(of: Set(satisfiedRequirements)))
    }

    /// Promote to VERIFIED only if every required step is satisfied; otherwise demote.
    public static func finalize(
        entityID: String,
        claim: String,
        result: String,
        requiredSteps: [String],
        satisfied: [String],
        failed: [String],
        unknown: [String],
        supportingEvidenceIDs: [String] = [],
        relationshipIDs: [String] = [],
        vendorRuleID: String? = nil
    ) -> VerificationChain {
        let conf: EvidenceConfidence
        var failure: String?
        if !failed.isEmpty {
            conf = .unknown
            failure = failed.joined(separator: ",")
        } else if !unknown.isEmpty {
            conf = .unknown
            failure = unknown.joined(separator: ",")
        } else if !requiredSteps.isEmpty, !Set(requiredSteps).isSubset(of: Set(satisfied)) {
            conf = .inferred
            failure = "REQUIRED_STEPS_INCOMPLETE"
        } else if satisfied.isEmpty && !requiredSteps.isEmpty {
            conf = .unknown
            failure = "NO_SATISFIED_STEPS"
        } else {
            conf = .verified
        }
        return VerificationChain(
            entityID: entityID,
            claim: claim,
            result: result,
            confidence: conf,
            supportingEvidenceIDs: supportingEvidenceIDs,
            relationshipIDs: relationshipIDs,
            vendorRuleID: vendorRuleID,
            requiredSteps: requiredSteps,
            satisfiedRequirements: satisfied,
            failedRequirements: failed,
            unknownRequirements: unknown,
            failureReason: failure
        )
    }
}

public enum VerificationChainBuilder {
    public static func build(for item: ClassifiedItem) -> [VerificationChain] {
        var chains: [VerificationChain] = []
        let id = item.detected.entity.id
        let rels = item.detected.annotation?.relationships ?? []
        let relIDs = rels.map { "\($0.type.rawValue):\($0.target):\($0.confidence.rawValue)" }
        let v = item.verification

        if let sot = v?.sourceOfTruth, sot.confidence == .verified || sot.value != .unknown {
            var sat: [String] = []
            var unk: [String] = []
            var fail: [String] = []
            let required = ["evidence_verified"]
            if sot.confidence == .verified { sat.append("evidence_verified") }
            else { unk.append(sot.reasonCode ?? "UNKNOWN") }
            chains.append(VerificationChain.finalize(
                entityID: id,
                claim: "SOURCE_OF_TRUTH",
                result: sot.value.rawValue,
                requiredSteps: required,
                satisfied: sat,
                failed: fail,
                unknown: unk,
                supportingEvidenceIDs: [sot.source.rawValue, sot.reasonCode].compactMap { $0 },
                relationshipIDs: relIDs
            ))
        }

        if let regen = v?.regenerable, regen.confidence == .verified || regen.value != .unknown {
            var sat: [String] = []
            var unk: [String] = []
            var fail: [String] = []
            let required = ["derived_from_verified", "regeneration_mechanism_known", "not_source_of_truth"]
            if rels.contains(where: { ($0.type == .derivedFrom || $0.type == .belongsToWorkspace) && $0.confidence == .verified && $0.presence == .present }) {
                sat.append("derived_from_verified")
            } else if item.detected.entity.path.lowercased().contains("deriveddata")
                        || item.detected.entity.path.lowercased().contains("node_modules") {
                unk.append("derived_from")
            } else {
                unk.append("derived_from")
            }
            if regen.confidence == .verified, regen.value == .true {
                sat.append("regeneration_mechanism_known")
            } else if regen.value == .true {
                fail.append("confidence_not_verified")
            }
            if v?.sourceOfTruth.value == .false, v?.sourceOfTruth.confidence == .verified {
                sat.append("not_source_of_truth")
            } else if regen.value == .true {
                unk.append("not_source_of_truth")
            }
            // For FALSE regenerable (SOT true), different required set
            if regen.value == .false, regen.confidence == .verified {
                chains.append(VerificationChain(
                    entityID: id,
                    claim: "REGENERABILITY",
                    result: regen.value.rawValue,
                    confidence: .verified,
                    supportingEvidenceIDs: [regen.source.rawValue, regen.reasonCode].compactMap { $0 },
                    relationshipIDs: relIDs,
                    vendorRuleID: v?.vendorRuleID ?? regen.reasonCode,
                    requiredSteps: ["source_of_truth_true"],
                    satisfiedRequirements: ["source_of_truth_true"]
                ))
            } else {
                chains.append(VerificationChain.finalize(
                    entityID: id,
                    claim: "REGENERABILITY",
                    result: regen.value.rawValue,
                    requiredSteps: required,
                    satisfied: sat,
                    failed: fail,
                    unknown: unk,
                    supportingEvidenceIDs: [regen.source.rawValue, regen.reasonCode].compactMap { $0 },
                    relationshipIDs: relIDs,
                    vendorRuleID: v?.vendorRuleID ?? regen.reasonCode
                ))
            }
        }

        if let active = v?.activeState, active != .unknown || v?.activeStateConfidence == .verified {
            var sat: [String] = []
            var unk: [String] = []
            let required = ["runtime_observation_verified"]
            if v?.activeStateConfidence == .verified { sat.append("runtime_observation_verified") }
            else { unk.append(UnknownReasonCode.unknownActiveState.rawValue) }
            chains.append(VerificationChain.finalize(
                entityID: id,
                claim: "ACTIVE_STATE",
                result: active.rawValue,
                requiredSteps: required,
                satisfied: sat,
                failed: [],
                unknown: unk,
                supportingEvidenceIDs: ["OPEN_FILE_SNAPSHOT", "PROCESS_SNAPSHOT"],
                relationshipIDs: relIDs.filter { $0.contains("REFERENCED_BY") }
            ))
        }

        for rel in rels where rel.confidence == .verified {
            let required = ["explicit_metadata", "target_resolved"]
            var sat = required
            var unk: [String] = []
            if rel.presence != .present {
                sat = ["explicit_metadata"]
                unk = ["target_resolved"]
            }
            chains.append(VerificationChain.finalize(
                entityID: id,
                claim: "RELATIONSHIP_\(rel.type.rawValue)",
                result: "\(rel.presence.rawValue):\(rel.target)",
                requiredSteps: required,
                satisfied: sat,
                failed: [],
                unknown: unk,
                supportingEvidenceIDs: ["RELATIONSHIP_METADATA"],
                relationshipIDs: ["\(rel.type.rawValue):\(rel.target)"]
            ))
        }
        return chains
    }

    public static func buildAll(_ items: [ClassifiedItem]) -> [VerificationChain] {
        items.flatMap(build(for:)).filter {
            $0.confidence == .verified || !$0.unknownRequirements.isEmpty || $0.failureReason != nil
        }
    }

    public static func strictVerifiedCount(_ chains: [VerificationChain]) -> Int {
        chains.filter(\.satisfiesStrictChain).count
    }
}

public struct VerifiedRelationshipCoverage: Codable, Sendable, Equatable {
    public var eligibleBytes: Int64
    public var bytesWithVerifiedRelationship: Int64
    public var entityCount: Int
    public var entitiesWithVerifiedRelationship: Int
    public var byType: [String: Int]

    public var byteCoveragePercent: Double {
        ByteAccountant.coverage(uniqueBytes: bytesWithVerifiedRelationship, scannedBytes: max(eligibleBytes, 1))
    }

    public var entityCoveragePercent: Double {
        guard entityCount > 0 else { return 0 }
        return Double(entitiesWithVerifiedRelationship) / Double(entityCount) * 100
    }

    public static func build(_ items: [ClassifiedItem]) -> VerifiedRelationshipCoverage {
        var eligible: Int64 = 0
        var withRel: Int64 = 0
        var entitiesWith = 0
        var byType: [String: Int] = [:]
        for item in items {
            eligible += item.exclusiveBytes
            let verified = (item.detected.annotation?.relationships ?? []).filter { $0.confidence == .verified }
            if !verified.isEmpty {
                withRel += item.exclusiveBytes
                entitiesWith += 1
                for r in verified {
                    byType[r.type.rawValue, default: 0] += 1
                }
            }
        }
        return VerifiedRelationshipCoverage(
            eligibleBytes: eligible,
            bytesWithVerifiedRelationship: withRel,
            entityCount: items.count,
            entitiesWithVerifiedRelationship: entitiesWith,
            byType: byType
        )
    }
}
