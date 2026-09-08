import Foundation
import SafetyCore

public struct P311RemoteReacquisitionReport: Codable, Sendable, Equatable {
    public var vendor: String
    public var entitiesAttempted: Int
    public var entitiesVerified: Int
    public var entitiesUnknown: Int
    public var entitiesConflicted: Int
    public var remoteRequests: Int
    public var remoteCacheHits: Int
    public var remoteCoalescedRequests: Int
    public var timeouts: Int
    public var authRequired: Int
    public var rateLimited: Int
    public var identityMismatches: Int
    public var verifiedUniqueBytes: Int64
    public var unknownUniqueBytes: Int64
    public var proofFreshnessSeconds: Int
    public var credentialsPersisted: Bool
    public var credentialsLogged: Bool
    public var fullModelDownloads: Bool

    public init(
        vendor: String,
        entitiesAttempted: Int,
        entitiesVerified: Int,
        entitiesUnknown: Int,
        entitiesConflicted: Int,
        remoteRequests: Int,
        remoteCacheHits: Int,
        remoteCoalescedRequests: Int,
        timeouts: Int,
        authRequired: Int,
        rateLimited: Int,
        identityMismatches: Int,
        verifiedUniqueBytes: Int64,
        unknownUniqueBytes: Int64,
        proofFreshnessSeconds: Int,
        credentialsPersisted: Bool = false,
        credentialsLogged: Bool = false,
        fullModelDownloads: Bool = false
    ) {
        self.vendor = vendor
        self.entitiesAttempted = entitiesAttempted
        self.entitiesVerified = entitiesVerified
        self.entitiesUnknown = entitiesUnknown
        self.entitiesConflicted = entitiesConflicted
        self.remoteRequests = remoteRequests
        self.remoteCacheHits = remoteCacheHits
        self.remoteCoalescedRequests = remoteCoalescedRequests
        self.timeouts = timeouts
        self.authRequired = authRequired
        self.rateLimited = rateLimited
        self.identityMismatches = identityMismatches
        self.verifiedUniqueBytes = verifiedUniqueBytes
        self.unknownUniqueBytes = unknownUniqueBytes
        self.proofFreshnessSeconds = proofFreshnessSeconds
        self.credentialsPersisted = credentialsPersisted
        self.credentialsLogged = credentialsLogged
        self.fullModelDownloads = fullModelDownloads
    }
}

public struct P311InventoryBeforeAfter: Codable, Sendable, Equatable {
    public var before: P31PlanBytes
    public var after: P31PlanBytes
    public var hfVerifyMoreBefore: Int64
    public var hfVerifyMoreAfter: Int64
    public var ollamaVerifyMoreBefore: Int64
    public var ollamaVerifyMoreAfter: Int64
    public var remoteVerifiedBytes: Int64
    public var remoteUnknownBytes: Int64
    public var vendorNativeVerifiedFutureBytes: Int64
    public var note: String

    public init(
        before: P31PlanBytes,
        after: P31PlanBytes,
        hfVerifyMoreBefore: Int64,
        hfVerifyMoreAfter: Int64,
        ollamaVerifyMoreBefore: Int64,
        ollamaVerifyMoreAfter: Int64,
        remoteVerifiedBytes: Int64,
        remoteUnknownBytes: Int64,
        vendorNativeVerifiedFutureBytes: Int64,
        note: String
    ) {
        self.before = before
        self.after = after
        self.hfVerifyMoreBefore = hfVerifyMoreBefore
        self.hfVerifyMoreAfter = hfVerifyMoreAfter
        self.ollamaVerifyMoreBefore = ollamaVerifyMoreBefore
        self.ollamaVerifyMoreAfter = ollamaVerifyMoreAfter
        self.remoteVerifiedBytes = remoteVerifiedBytes
        self.remoteUnknownBytes = remoteUnknownBytes
        self.vendorNativeVerifiedFutureBytes = vendorNativeVerifiedFutureBytes
        self.note = note
    }
}

public struct P311RemotePerformanceReport: Codable, Sendable, Equatable {
    public var timeToFirstUsefulMapMs: Int?
    public var remoteProofStartMs: Int?
    public var remoteProofTotalMs: Int
    public var hfRemoteMs: Int
    public var ollamaRemoteMs: Int
    public var remoteRequestCount: Int
    public var remoteBytesReceived: Int
    public var timeouts: Int
    public var safetyCompletionMs: Int?
    public var firstMapRegressionPercent: Double?
    public var networkOnFirstMapPath: Bool

    public init(
        timeToFirstUsefulMapMs: Int?,
        remoteProofStartMs: Int?,
        remoteProofTotalMs: Int,
        hfRemoteMs: Int,
        ollamaRemoteMs: Int,
        remoteRequestCount: Int,
        remoteBytesReceived: Int,
        timeouts: Int,
        safetyCompletionMs: Int?,
        firstMapRegressionPercent: Double?,
        networkOnFirstMapPath: Bool = false
    ) {
        self.timeToFirstUsefulMapMs = timeToFirstUsefulMapMs
        self.remoteProofStartMs = remoteProofStartMs
        self.remoteProofTotalMs = remoteProofTotalMs
        self.hfRemoteMs = hfRemoteMs
        self.ollamaRemoteMs = ollamaRemoteMs
        self.remoteRequestCount = remoteRequestCount
        self.remoteBytesReceived = remoteBytesReceived
        self.timeouts = timeouts
        self.safetyCompletionMs = safetyCompletionMs
        self.firstMapRegressionPercent = firstMapRegressionPercent
        self.networkOnFirstMapPath = networkOnFirstMapPath
    }
}

public enum P311ReportBuilder {
    public static func remoteReports(
        proofs: [RemoteReacquisitionProof],
        sessionStats: (requests: Int, hits: Int, coalesced: Int, bytes: Int, timeouts: Int)?,
        freshnessSeconds: Int = RemoteNetworkBudget.default.freshnessSeconds
    ) -> [P311RemoteReacquisitionReport] {
        let grouped = Dictionary(grouping: proofs, by: \.vendor)
        return VendorStorageKind.allCases.compactMap { vendor -> P311RemoteReacquisitionReport? in
            let list = grouped[vendor] ?? []
            guard !list.isEmpty || vendor == .huggingFace || vendor == .ollama else { return nil }
            let verified = list.filter { $0.status == .verified }
            let unknown = list.filter {
                [.unknown, .timeout, .authRequired, .rateLimited, .accessUnknown, .remoteUnavailable, .notApplicable].contains($0.status)
            }
            let conflicted = list.filter { $0.status == .conflicted || $0.status == .identityMismatch }
            return P311RemoteReacquisitionReport(
                vendor: vendor.rawValue,
                entitiesAttempted: list.count,
                entitiesVerified: verified.count,
                entitiesUnknown: unknown.count,
                entitiesConflicted: conflicted.count,
                remoteRequests: sessionStats?.requests ?? 0,
                remoteCacheHits: sessionStats?.hits ?? 0,
                remoteCoalescedRequests: sessionStats?.coalesced ?? 0,
                timeouts: list.filter { $0.status == .timeout }.count + (sessionStats?.timeouts ?? 0),
                authRequired: list.filter { $0.status == .authRequired }.count,
                rateLimited: list.filter { $0.status == .rateLimited }.count,
                identityMismatches: list.filter { $0.status == .identityMismatch }.count,
                verifiedUniqueBytes: verified.compactMap(\.estimatedRedownloadBytes).reduce(0, +),
                unknownUniqueBytes: unknown.compactMap(\.estimatedRedownloadBytes).reduce(0, +),
                proofFreshnessSeconds: freshnessSeconds
            )
        }
    }
}
