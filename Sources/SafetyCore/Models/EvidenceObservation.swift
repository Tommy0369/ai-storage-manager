import Foundation

public enum ObservationCompleteness: String, Codable, Sendable, Equatable {
    case complete = "COMPLETE"
    case partial = "PARTIAL"
    case unknown = "UNKNOWN"
}

public enum EvidenceSourceKind: String, Codable, Sendable, Equatable {
    case filesystemMetadata = "FILESYSTEM_METADATA"
    case processSnapshot = "PROCESS_SNAPSHOT"
    case openFileSnapshot = "OPEN_FILE_SNAPSHOT"
    case appMetadata = "APP_METADATA"
    case manifest = "MANIFEST"
    case lockfile = "LOCKFILE"
    case vendorRule = "VENDOR_RULE"
    case fileProviderMetadata = "FILE_PROVIDER_METADATA"
    case relationshipMetadata = "RELATIONSHIP_METADATA"
    case unknown = "UNKNOWN"
}

public struct ObservationRecord: Codable, Sendable, Equatable {
    public var value: PredicateValue
    public var confidence: EvidenceConfidence
    public var completeness: ObservationCompleteness
    public var source: EvidenceSourceKind
    public var observedAt: Date
    public var reasonCode: String?

    public init(
        value: PredicateValue,
        confidence: EvidenceConfidence,
        completeness: ObservationCompleteness,
        source: EvidenceSourceKind,
        observedAt: Date = Date(),
        reasonCode: String? = nil
    ) {
        self.value = value
        self.confidence = confidence
        self.completeness = completeness
        self.source = source
        self.observedAt = observedAt
        self.reasonCode = reasonCode
    }

    /// Negative evidence is only VERIFIED false when observation is COMPLETE.
    public static func negativeOrUnknown(
        found: Bool,
        completeness: ObservationCompleteness,
        source: EvidenceSourceKind,
        incompleteReason: String
    ) -> ObservationRecord {
        if completeness != .complete {
            return ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: completeness,
                source: source,
                reasonCode: incompleteReason
            )
        }
        return ObservationRecord(
            value: found ? .true : .false,
            confidence: .verified,
            completeness: .complete,
            source: source
        )
    }

    public var satisfiesStrictPredicate: Bool {
        value == .true && confidence == .verified
    }
}

public struct VerificationAnnotation: Codable, Sendable, Equatable {
    public var sourceOfTruth: ObservationRecord
    public var regenerable: ObservationRecord
    public var activeState: ObservedActiveState
    public var activeStateConfidence: EvidenceConfidence
    public var activeStateCompleteness: ObservationCompleteness
    public var provenanceConfidence: EvidenceConfidence
    public var unknownReasons: [String]
    public var vendorRuleID: String?
    public var reconstructionMechanism: String?
    /// Vendor proof notes (identity, shared bytes, blockers). Evidence only — not SafetyClass.
    public var vendorProofNotes: [String]
    public var logicalBytesProven: Int64?
    public var uniqueBytesProven: Int64?
    public var sharedBytesProven: Int64?
    public var referenceGraphConfidence: EvidenceConfidence
    public var reacquisition: ObservationRecord
    public var remoteReacquisitionProof: RemoteReacquisitionProof?
    public var estimatedRedownloadBytes: Int64?

    public init(
        sourceOfTruth: ObservationRecord = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .unknown, source: .unknown),
        regenerable: ObservationRecord = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .unknown, source: .unknown),
        activeState: ObservedActiveState = .unknown,
        activeStateConfidence: EvidenceConfidence = .unknown,
        activeStateCompleteness: ObservationCompleteness = .unknown,
        provenanceConfidence: EvidenceConfidence = .unknown,
        unknownReasons: [String] = [],
        vendorRuleID: String? = nil,
        reconstructionMechanism: String? = nil,
        vendorProofNotes: [String] = [],
        logicalBytesProven: Int64? = nil,
        uniqueBytesProven: Int64? = nil,
        sharedBytesProven: Int64? = nil,
        referenceGraphConfidence: EvidenceConfidence = .unknown,
        reacquisition: ObservationRecord = ObservationRecord(value: .unknown, confidence: .unknown, completeness: .unknown, source: .unknown),
        remoteReacquisitionProof: RemoteReacquisitionProof? = nil,
        estimatedRedownloadBytes: Int64? = nil
    ) {
        self.sourceOfTruth = sourceOfTruth
        self.regenerable = regenerable
        self.activeState = activeState
        self.activeStateConfidence = activeStateConfidence
        self.activeStateCompleteness = activeStateCompleteness
        self.provenanceConfidence = provenanceConfidence
        self.unknownReasons = unknownReasons
        self.vendorRuleID = vendorRuleID
        self.reconstructionMechanism = reconstructionMechanism
        self.vendorProofNotes = vendorProofNotes
        self.logicalBytesProven = logicalBytesProven
        self.uniqueBytesProven = uniqueBytesProven
        self.sharedBytesProven = sharedBytesProven
        self.referenceGraphConfidence = referenceGraphConfidence
        self.reacquisition = reacquisition
        self.remoteReacquisitionProof = remoteReacquisitionProof
        self.estimatedRedownloadBytes = estimatedRedownloadBytes
    }
}

public struct VerificationCoverage: Codable, Sendable, Equatable {
    public var eligibleBytes: Int64
    public var provenanceVerifiedBytes: Int64
    public var provenanceInferredBytes: Int64
    public var provenanceUnknownBytes: Int64
    public var sourceOfTruthKnownBytes: Int64
    public var regenerabilityKnownBytes: Int64
    public var runtimeStateKnownBytes: Int64
    public var verifiedRelationshipBytes: Int64
    public var domain: [DomainVerificationCoverage]

    public var provenanceVerifiedPercent: Double {
        ByteAccountant.coverage(uniqueBytes: provenanceVerifiedBytes, scannedBytes: max(eligibleBytes, 1))
    }
    public var sourceOfTruthKnownPercent: Double {
        ByteAccountant.coverage(uniqueBytes: sourceOfTruthKnownBytes, scannedBytes: max(eligibleBytes, 1))
    }
    public var regenerabilityKnownPercent: Double {
        ByteAccountant.coverage(uniqueBytes: regenerabilityKnownBytes, scannedBytes: max(eligibleBytes, 1))
    }
    public var runtimeStateKnownPercent: Double {
        ByteAccountant.coverage(uniqueBytes: runtimeStateKnownBytes, scannedBytes: max(eligibleBytes, 1))
    }
    public var verifiedRelationshipPercent: Double {
        ByteAccountant.coverage(uniqueBytes: verifiedRelationshipBytes, scannedBytes: max(eligibleBytes, 1))
    }
}

public struct DomainVerificationCoverage: Codable, Sendable, Equatable {
    public var domain: String
    public var eligibleBytes: Int64
    public var provenanceVerifiedPercent: Double
    public var sourceOfTruthKnownPercent: Double
    public var regenerabilityKnownPercent: Double
    public var runtimeStateKnownPercent: Double
}

public enum VerificationCoverageBuilder {
    public static func build(_ items: [ClassifiedItem]) -> VerificationCoverage {
        var eligible: Int64 = 0
        var provV: Int64 = 0, provI: Int64 = 0, provU: Int64 = 0
        var sot: Int64 = 0, regen: Int64 = 0, runtime: Int64 = 0, relB: Int64 = 0
        var byDomain: [String: (Int64, Int64, Int64, Int64, Int64)] = [:]
        for item in items {
            let b = item.exclusiveBytes
            eligible += b
            let v = item.verification
            let prov = v?.provenanceConfidence
                ?? item.detected.annotation?.provenance.confidence
                ?? .unknown
            switch prov {
            case .verified: provV += b
            case .inferred: provI += b
            case .unknown: provU += b
            }
            let sotKnown = v?.sourceOfTruth.confidence == .verified && (v?.sourceOfTruth.value == .true || v?.sourceOfTruth.value == .false)
            let regenKnown = v?.regenerable.confidence == .verified && (v?.regenerable.value == .true || v?.regenerable.value == .false)
            let runtimeKnown = v?.activeStateConfidence == .verified && v?.activeState != .unknown
            let hasVerifiedRel = (item.detected.annotation?.relationships ?? []).contains { $0.confidence == .verified }
            if sotKnown { sot += b }
            if regenKnown { regen += b }
            if runtimeKnown { runtime += b }
            if hasVerifiedRel { relB += b }
            var row = byDomain[item.detected.domain] ?? (0, 0, 0, 0, 0)
            row.0 += b
            if prov == .verified { row.1 += b }
            if sotKnown { row.2 += b }
            if regenKnown { row.3 += b }
            if runtimeKnown { row.4 += b }
            byDomain[item.detected.domain] = row
        }
        let domains = byDomain.keys.sorted().map { d -> DomainVerificationCoverage in
            let r = byDomain[d]!
            let denom = max(r.0, 1)
            return DomainVerificationCoverage(
                domain: d,
                eligibleBytes: r.0,
                provenanceVerifiedPercent: ByteAccountant.coverage(uniqueBytes: r.1, scannedBytes: denom),
                sourceOfTruthKnownPercent: ByteAccountant.coverage(uniqueBytes: r.2, scannedBytes: denom),
                regenerabilityKnownPercent: ByteAccountant.coverage(uniqueBytes: r.3, scannedBytes: denom),
                runtimeStateKnownPercent: ByteAccountant.coverage(uniqueBytes: r.4, scannedBytes: denom)
            )
        }
        return VerificationCoverage(
            eligibleBytes: eligible,
            provenanceVerifiedBytes: provV,
            provenanceInferredBytes: provI,
            provenanceUnknownBytes: provU,
            sourceOfTruthKnownBytes: sot,
            regenerabilityKnownBytes: regen,
            runtimeStateKnownBytes: runtime,
            verifiedRelationshipBytes: relB,
            domain: domains
        )
    }
}
