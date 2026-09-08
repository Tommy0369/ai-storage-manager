import Foundation

/// P3.2B.4 — dry-run preview vs post-action actual.
/// Byte equality with vendor formatting (e.g. "3.1G") is NOT required.
public struct VendorPreviewOutcomeComparison: Codable, Sendable, Equatable {
    public var targetMatch: Bool
    public var revisionCountMatch: Bool
    public var repoRemovalConsequenceMatch: Bool
    public var expectedFreedBytes: Int64?
    public var verifiedRecoveredBytes: Int64
    public var sizeDifference: Int64?
    public var sizeSemanticsCompatible: Bool
    public var logicalConsequenceMatched: Bool
    public var unexpectedEffects: Bool
    public var previewRevisionCount: Int?
    public var actualRevisionRemoved: Bool
    public var previewRepoRemovalExpected: Bool
    public var actualRepoRemoved: Bool
    public var previewVendorFreedLabel: String?
    public var diskFreeObserved: Int64?

    public init(
        targetMatch: Bool,
        revisionCountMatch: Bool,
        repoRemovalConsequenceMatch: Bool,
        expectedFreedBytes: Int64? = nil,
        verifiedRecoveredBytes: Int64,
        sizeDifference: Int64? = nil,
        sizeSemanticsCompatible: Bool,
        logicalConsequenceMatched: Bool,
        unexpectedEffects: Bool,
        previewRevisionCount: Int? = nil,
        actualRevisionRemoved: Bool,
        previewRepoRemovalExpected: Bool,
        actualRepoRemoved: Bool,
        previewVendorFreedLabel: String? = nil,
        diskFreeObserved: Int64? = nil
    ) {
        self.targetMatch = targetMatch
        self.revisionCountMatch = revisionCountMatch
        self.repoRemovalConsequenceMatch = repoRemovalConsequenceMatch
        self.expectedFreedBytes = expectedFreedBytes
        self.verifiedRecoveredBytes = verifiedRecoveredBytes
        self.sizeDifference = sizeDifference
        self.sizeSemanticsCompatible = sizeSemanticsCompatible
        self.logicalConsequenceMatched = logicalConsequenceMatched
        self.unexpectedEffects = unexpectedEffects
        self.previewRevisionCount = previewRevisionCount
        self.actualRevisionRemoved = actualRevisionRemoved
        self.previewRepoRemovalExpected = previewRepoRemovalExpected
        self.actualRepoRemoved = actualRepoRemoved
        self.previewVendorFreedLabel = previewVendorFreedLabel
        self.diskFreeObserved = diskFreeObserved
    }

    /// Vendor "3.1G" telemetry vs semantic 3,083,520,968 — formatting difference is compatible.
    public static func sizeSemanticsCompatible(
        vendorReportedApprox: Int64?,
        verifiedRecovered: Int64,
        toleranceRatio: Double = 0.05
    ) -> Bool {
        guard let vendor = vendorReportedApprox, vendor > 0, verifiedRecovered > 0 else {
            return true
        }
        let diff = abs(Double(vendor - verifiedRecovered))
        return diff / Double(max(vendor, verifiedRecovered)) <= toleranceRatio
    }

    public static func forP32B3RealAction(
        verifiedRecovered: Int64 = 3_083_520_968,
        vendorApprox: Int64 = 3_100_000_000,
        diskFree: Int64 = 3_083_640_832
    ) -> VendorPreviewOutcomeComparison {
        let sizeOK = sizeSemanticsCompatible(
            vendorReportedApprox: vendorApprox,
            verifiedRecovered: verifiedRecovered
        )
        return VendorPreviewOutcomeComparison(
            targetMatch: true,
            revisionCountMatch: true,
            repoRemovalConsequenceMatch: true,
            expectedFreedBytes: vendorApprox,
            verifiedRecoveredBytes: verifiedRecovered,
            sizeDifference: vendorApprox - verifiedRecovered,
            sizeSemanticsCompatible: sizeOK,
            logicalConsequenceMatched: true,
            unexpectedEffects: false,
            previewRevisionCount: 1,
            actualRevisionRemoved: true,
            previewRepoRemovalExpected: true,
            actualRepoRemoved: true,
            previewVendorFreedLabel: "~3.1G",
            diskFreeObserved: diskFree
        )
    }

    /// Multi-revision fixture: target A removed, B retained, repo dir remains.
    public static func forMultiRevisionFixture(
        verifiedRecovered: Int64
    ) -> VendorPreviewOutcomeComparison {
        VendorPreviewOutcomeComparison(
            targetMatch: true,
            revisionCountMatch: true,
            repoRemovalConsequenceMatch: true,
            expectedFreedBytes: verifiedRecovered,
            verifiedRecoveredBytes: verifiedRecovered,
            sizeDifference: 0,
            sizeSemanticsCompatible: true,
            logicalConsequenceMatched: true,
            unexpectedEffects: false,
            previewRevisionCount: 2,
            actualRevisionRemoved: true,
            previewRepoRemovalExpected: false,
            actualRepoRemoved: false,
            previewVendorFreedLabel: nil,
            diskFreeObserved: nil
        )
    }
}
