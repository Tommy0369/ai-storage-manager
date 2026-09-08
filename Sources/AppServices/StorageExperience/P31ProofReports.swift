import Foundation
import SafetyCore

public struct P31ProofCoverageReport: Codable, Sendable, Equatable {
    public var vendor: String
    public var entityCount: Int
    public var totalBytesObserved: Int64
    public var exactEntities: Int
    public var claimsAttempted: Int
    public var claimsVerified: Int
    public var claimsUnknown: Int
    public var claimsConflicted: Int
    public var sourceIdentityVerifiedCount: Int
    public var referenceGraphVerifiedCount: Int
    public var sharedByteKnownCount: Int
    public var runtimeVerifiedCount: Int
    public var reacquirabilityVerifiedCount: Int
    public var actionDecisionCounts: [String: Int]
    public var verifiedFuturePotentialBytes: Int64
    public var readyNowPotentialBytes: Int64
    public var falseGREEN: Int
    public var duplicateEvaluations: Int

    public init(
        vendor: String,
        entityCount: Int,
        totalBytesObserved: Int64,
        exactEntities: Int,
        claimsAttempted: Int,
        claimsVerified: Int,
        claimsUnknown: Int,
        claimsConflicted: Int,
        sourceIdentityVerifiedCount: Int,
        referenceGraphVerifiedCount: Int,
        sharedByteKnownCount: Int,
        runtimeVerifiedCount: Int,
        reacquirabilityVerifiedCount: Int,
        actionDecisionCounts: [String: Int],
        verifiedFuturePotentialBytes: Int64,
        readyNowPotentialBytes: Int64,
        falseGREEN: Int,
        duplicateEvaluations: Int
    ) {
        self.vendor = vendor
        self.entityCount = entityCount
        self.totalBytesObserved = totalBytesObserved
        self.exactEntities = exactEntities
        self.claimsAttempted = claimsAttempted
        self.claimsVerified = claimsVerified
        self.claimsUnknown = claimsUnknown
        self.claimsConflicted = claimsConflicted
        self.sourceIdentityVerifiedCount = sourceIdentityVerifiedCount
        self.referenceGraphVerifiedCount = referenceGraphVerifiedCount
        self.sharedByteKnownCount = sharedByteKnownCount
        self.runtimeVerifiedCount = runtimeVerifiedCount
        self.reacquirabilityVerifiedCount = reacquirabilityVerifiedCount
        self.actionDecisionCounts = actionDecisionCounts
        self.verifiedFuturePotentialBytes = verifiedFuturePotentialBytes
        self.readyNowPotentialBytes = readyNowPotentialBytes
        self.falseGREEN = falseGREEN
        self.duplicateEvaluations = duplicateEvaluations
    }
}

public struct P31AIModelInventoryReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var entities: [P31InventoryEntity]
    public var privacyNote: String

    public init(generatedAt: Date, entities: [P31InventoryEntity], privacyNote: String) {
        self.generatedAt = generatedAt
        self.entities = entities
        self.privacyNote = privacyNote
    }
}

public struct P31InventoryEntity: Codable, Sendable, Equatable {
    public var vendor: String
    public var entityType: String
    public var displayIdentity: String
    public var logicalBytes: Int64
    public var uniqueBytes: Int64?
    public var sharedBytes: Int64?
    public var originRevisionState: String
    public var runtimeState: String
    public var reacquisitionState: String
    public var actionDecisions: [String]
    public var topBlockers: [String]

    public init(
        vendor: String,
        entityType: String,
        displayIdentity: String,
        logicalBytes: Int64,
        uniqueBytes: Int64?,
        sharedBytes: Int64?,
        originRevisionState: String,
        runtimeState: String,
        reacquisitionState: String,
        actionDecisions: [String],
        topBlockers: [String]
    ) {
        self.vendor = vendor
        self.entityType = entityType
        self.displayIdentity = displayIdentity
        self.logicalBytes = logicalBytes
        self.uniqueBytes = uniqueBytes
        self.sharedBytes = sharedBytes
        self.originRevisionState = originRevisionState
        self.runtimeState = runtimeState
        self.reacquisitionState = reacquisitionState
        self.actionDecisions = actionDecisions
        self.topBlockers = topBlockers
    }
}

public struct P31CandidateInventoryBeforeAfter: Codable, Sendable, Equatable {
    public var before: P31PlanBytes
    public var after: P31PlanBytes
    public var hfUnresolvedBefore: Int64
    public var hfUnresolvedAfter: Int64
    public var ollamaUnresolvedBefore: Int64
    public var ollamaUnresolvedAfter: Int64
    public var note: String

    public init(
        before: P31PlanBytes,
        after: P31PlanBytes,
        hfUnresolvedBefore: Int64,
        hfUnresolvedAfter: Int64,
        ollamaUnresolvedBefore: Int64,
        ollamaUnresolvedAfter: Int64,
        note: String
    ) {
        self.before = before
        self.after = after
        self.hfUnresolvedBefore = hfUnresolvedBefore
        self.hfUnresolvedAfter = hfUnresolvedAfter
        self.ollamaUnresolvedBefore = ollamaUnresolvedBefore
        self.ollamaUnresolvedAfter = ollamaUnresolvedAfter
        self.note = note
    }
}

public struct P31PlanBytes: Codable, Sendable, Equatable {
    public var readyNowBytes: Int64
    public var verifiedFutureBytes: Int64
    public var verifyMoreBytes: Int64
    public var protectedBytes: Int64

    public init(
        readyNowBytes: Int64,
        verifiedFutureBytes: Int64,
        verifyMoreBytes: Int64,
        protectedBytes: Int64
    ) {
        self.readyNowBytes = readyNowBytes
        self.verifiedFutureBytes = verifiedFutureBytes
        self.verifyMoreBytes = verifyMoreBytes
        self.protectedBytes = protectedBytes
    }
}

public struct P31ProofPerformanceReport: Codable, Sendable, Equatable {
    public var timeToFirstUsefulMapMs: Int?
    public var hfProofMs: Int
    public var ollamaProofMs: Int
    public var remoteProofMs: Int
    public var vendorCLICalls: Int
    public var metadataReads: Int
    public var proofClaimsAttempted: Int
    public var proofClaimsVerified: Int
    public var proofClaimsUnknown: Int
    public var safetyCompletionMs: Int?
    public var firstMapRegressionPercent: Double?

    public init(
        timeToFirstUsefulMapMs: Int?,
        hfProofMs: Int,
        ollamaProofMs: Int,
        remoteProofMs: Int,
        vendorCLICalls: Int,
        metadataReads: Int,
        proofClaimsAttempted: Int,
        proofClaimsVerified: Int,
        proofClaimsUnknown: Int,
        safetyCompletionMs: Int?,
        firstMapRegressionPercent: Double?
    ) {
        self.timeToFirstUsefulMapMs = timeToFirstUsefulMapMs
        self.hfProofMs = hfProofMs
        self.ollamaProofMs = ollamaProofMs
        self.remoteProofMs = remoteProofMs
        self.vendorCLICalls = vendorCLICalls
        self.metadataReads = metadataReads
        self.proofClaimsAttempted = proofClaimsAttempted
        self.proofClaimsVerified = proofClaimsVerified
        self.proofClaimsUnknown = proofClaimsUnknown
        self.safetyCompletionMs = safetyCompletionMs
        self.firstMapRegressionPercent = firstMapRegressionPercent
    }
}

public enum P31ReportBuilder {
    public static func coverage(
        inventories: [VendorProofInventory],
        actionDecisionCounts: [String: Int],
        verifiedFuture: Int64,
        readyNow: Int64,
        falseGREEN: Int,
        duplicateEvaluations: Int
    ) -> [P31ProofCoverageReport] {
        inventories.map { inv in
            let exact = inv.entities.filter {
                $0.entityKind == .model || $0.entityKind == .repository || $0.entityKind == .snapshot
            }.count
            return P31ProofCoverageReport(
                vendor: inv.vendor.rawValue,
                entityCount: inv.entities.count,
                totalBytesObserved: inv.entities.first?.logicalBytes
                    ?? inv.blobs.compactMap(\.bytes).reduce(0, +),
                exactEntities: exact,
                claimsAttempted: inv.claimsAttempted,
                claimsVerified: inv.claimsVerified,
                claimsUnknown: inv.claimsUnknown,
                claimsConflicted: inv.claimsConflicted,
                sourceIdentityVerifiedCount: inv.entities.filter { $0.originIdentity != nil && $0.provenanceConfidence == .verified }.count,
                referenceGraphVerifiedCount: inv.entities.filter(\.referenceGraphComplete).count,
                sharedByteKnownCount: inv.entities.filter { $0.sharedBytes != nil }.count,
                runtimeVerifiedCount: inv.entities.filter { $0.runtimeConfidence == .verified }.count,
                reacquirabilityVerifiedCount: inv.entities.filter { $0.reacquisitionConfidence == .verified }.count,
                actionDecisionCounts: actionDecisionCounts,
                verifiedFuturePotentialBytes: verifiedFuture,
                readyNowPotentialBytes: readyNow,
                falseGREEN: falseGREEN,
                duplicateEvaluations: duplicateEvaluations
            )
        }
    }

    public static func inventory(
        from inventories: [VendorProofInventory],
        remoteProofs: [RemoteReacquisitionProof] = []
    ) -> P31AIModelInventoryReport {
        let byID = Dictionary(uniqueKeysWithValues: remoteProofs.map { ($0.entityID, $0) })
        let entities = inventories.flatMap(\.entities).map { e -> P31InventoryEntity in
            let remote = byID[e.entityID]
            let reacq = remote.map { "\($0.status.rawValue)/\($0.confidence.rawValue)" }
                ?? "\(e.reacquisition.rawValue)/\(e.reacquisitionConfidence.rawValue)"
            var blockers = e.topBlockers
            if let remote, remote.isStrictVerified {
                blockers.removeAll { $0 == "REACQUISITION_REMOTE_UNKNOWN" }
                if !blockers.contains("VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE") {
                    blockers.append("VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE")
                }
            } else if let remote {
                switch remote.status {
                case .authRequired:
                    blockers.removeAll { $0 == "REACQUISITION_REMOTE_UNKNOWN" }
                    if !blockers.contains("AUTH_REQUIRED") { blockers.append("AUTH_REQUIRED") }
                case .identityMismatch:
                    blockers.removeAll { $0 == "REACQUISITION_REMOTE_UNKNOWN" }
                    if !blockers.contains("REMOTE_IDENTITY_MISMATCH") { blockers.append("REMOTE_IDENTITY_MISMATCH") }
                case .rateLimited:
                    blockers.removeAll { $0 == "REACQUISITION_REMOTE_UNKNOWN" }
                    if !blockers.contains("RATE_LIMITED") { blockers.append("RATE_LIMITED") }
                case .timeout, .remoteUnavailable, .accessUnknown, .unknown, .conflicted:
                    if !blockers.contains("REACQUISITION_REMOTE_UNKNOWN") {
                        blockers.append("REACQUISITION_REMOTE_UNKNOWN")
                    }
                case .verified, .notApplicable:
                    break
                }
            }
            return P31InventoryEntity(
                vendor: e.vendor.rawValue,
                entityType: e.entityKind.rawValue,
                displayIdentity: e.displayIdentity,
                logicalBytes: e.logicalBytes,
                uniqueBytes: e.uniqueBytes,
                sharedBytes: e.sharedBytes,
                originRevisionState: [e.originIdentity, e.revisionIdentity].compactMap { $0 }.joined(separator: "@"),
                runtimeState: "\(e.runtimeState.rawValue)/\(e.runtimeConfidence.rawValue)",
                reacquisitionState: reacq,
                actionDecisions: [e.preferredActionHint?.rawValue ?? "KEEP"],
                topBlockers: blockers
            )
        }
        return P31AIModelInventoryReport(
            generatedAt: Date(),
            entities: entities,
            privacyNote: "No secrets/tokens included. Display identities only."
        )
    }

    public static func performance(
        firstMapMs: Int?,
        inventories: [VendorProofInventory],
        safetyMs: Int?,
        baselineFirstMapMs: Int = 1_021
    ) -> P31ProofPerformanceReport {
        let hf = inventories.first { $0.vendor == .huggingFace }
        let ol = inventories.first { $0.vendor == .ollama }
        let attempted = inventories.reduce(0) { $0 + $1.claimsAttempted }
        let verified = inventories.reduce(0) { $0 + $1.claimsVerified }
        let unknown = inventories.reduce(0) { $0 + $1.claimsUnknown }
        let regression: Double?
        if let firstMapMs {
            regression = Double(firstMapMs - baselineFirstMapMs) / Double(max(baselineFirstMapMs, 1)) * 100
        } else {
            regression = nil
        }
        return P31ProofPerformanceReport(
            timeToFirstUsefulMapMs: firstMapMs,
            hfProofMs: hf?.proofRuntimeMs ?? 0,
            ollamaProofMs: ol?.proofRuntimeMs ?? 0,
            remoteProofMs: 0,
            vendorCLICalls: inventories.reduce(0) { $0 + $1.vendorCLICalls },
            metadataReads: inventories.reduce(0) { $0 + $1.metadataReads },
            proofClaimsAttempted: attempted,
            proofClaimsVerified: verified,
            proofClaimsUnknown: unknown,
            safetyCompletionMs: safetyMs,
            firstMapRegressionPercent: regression
        )
    }
}
