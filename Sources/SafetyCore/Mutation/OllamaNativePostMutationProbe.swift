import Foundation

/// Read-only before/after evidence for Ollama MODEL × VENDOR_NATIVE_CLEANUP.
/// Never deletes blobs. Never copies potential bytes into verified recovery.
public enum OllamaNativePostMutationProbe {
    public static let authorizedEntityID = "ai.ollama.model.library.qwen3:4b"
    public static let authorizedCanonicalModel = "library/qwen3:4b"
    public static let authorizedAction = StorageAction.vendorNativeCleanup
    public static let authorizationText = "library/qwen3:4b の Ollama native削除を承認する。"

    public struct BeforeSnapshot: Sendable, Equatable {
        public var entityID: String
        public var canonicalModel: String
        public var modelPresent: Bool
        public var uniqueBytes: Int64
        public var sharedBytes: Int64
        public var exclusiveDigestBytes: [String: Int64]
        public var manifestPath: String
        public var freeBytes: Int64?
        public var observedAt: Date
    }

    public struct AfterEvidence: Sendable, Equatable {
        public var modelPresent: Bool
        public var inventoryFailure: String?
        public var oldManifestPresent: Bool
        public var remainingReferencedBlobCount: Int
        public var remainingUniqueBytes: Int64
        public var remainingSharedBytes: Int64
        public var exclusiveDigestsStillPresent: Int
        public var exclusiveDigestBytesGone: Int64
        public var freeBytes: Int64?
        public var mappedDeltaBytes: Int64?
        public var diskFreeDeltaBytes: Int64?
        public var regenerationDetected: Bool
        public var observedAt: Date
    }

    public static func authorizationTextFingerprint(_ text: String = authorizationText) -> String {
        ActionBindingFingerprintBuilder.stablePublicHash(text)
    }

    public static func captureBefore(
        entityID: String,
        canonicalModel: String,
        item: ClassifiedItem,
        cliURL: URL,
        runner: any BoundedProcessRunner,
        now: Date = Date()
    ) -> BeforeSnapshot {
        let inventory = OllamaInstalledModelInventory.capture(cliURL: cliURL, runner: runner, now: now)
        let present = OllamaInstalledModelInventory.recognition(
            targetCanonical: canonicalModel,
            inventory: inventory
        ) == .recognizedExact
        let semantic = VendorStorageProofIndex.entity(id: entityID)
            ?? VendorStorageProofIndex.lookup(pathOrID: item.detected.entity.path)
        let unique = item.verification?.uniqueBytesProven
            ?? semantic?.uniqueBytes
            ?? item.exclusiveBytes
        let shared = item.verification?.sharedBytesProven ?? semantic?.sharedBytes ?? 0
        var exclusive: [String: Int64] = [:]
        if let semantic {
            let root = modelsRoot(from: item.detected.entity.path)
            if let inv = VendorStorageProofIndex.inventory(forRoot: root) {
                let digests = Set(semantic.referencedBlobDigests)
                for blob in inv.blobs where digests.contains(blob.digest) && blob.scope == .exclusive {
                    exclusive[blob.digest] = blob.bytes ?? 0
                }
            }
        }
        let manifest = manifestPath(for: canonicalModel, itemPath: item.detected.entity.path)
        return BeforeSnapshot(
            entityID: entityID,
            canonicalModel: canonicalModel,
            modelPresent: present,
            uniqueBytes: unique,
            sharedBytes: shared,
            exclusiveDigestBytes: exclusive,
            manifestPath: manifest,
            freeBytes: StorageCapacityMeasurer.freeBytes(),
            observedAt: now
        )
    }

    public static func observeAfter(
        before: BeforeSnapshot,
        cliURL: URL,
        runner: any BoundedProcessRunner,
        settleMs: Int = 800,
        now: Date = Date()
    ) -> AfterEvidence {
        if settleMs > 0 {
            Thread.sleep(forTimeInterval: Double(settleMs) / 1000.0)
        }
        var inventory = OllamaInstalledModelInventory.capture(cliURL: cliURL, runner: runner, now: now)
        var present = OllamaInstalledModelInventory.recognition(
            targetCanonical: before.canonicalModel,
            inventory: inventory
        ) == .recognizedExact
        // One bounded inventory retry if vendor metadata lags.
        if present == before.modelPresent, before.modelPresent {
            Thread.sleep(forTimeInterval: 0.6)
            inventory = OllamaInstalledModelInventory.capture(cliURL: cliURL, runner: runner, now: Date())
            present = OllamaInstalledModelInventory.recognition(
                targetCanonical: before.canonicalModel,
                inventory: inventory
            ) == .recognizedExact
        }

        let root = modelsRoot(from: before.manifestPath)
        VendorStorageProofIndex.invalidate(forRoot: root)
        let rebuilt = OllamaStorageProofProvider(allowCLI: false).prove(rootPath: root, budgetMs: 8_000)
        let afterEntity = rebuilt.entities.first { $0.entityID == before.entityID }
        let remainingUnique = afterEntity?.uniqueBytes ?? 0
        let remainingShared = afterEntity?.sharedBytes ?? 0
        let remainingRefs = afterEntity?.referencedBlobDigests.count ?? 0

        var stillPresent = 0
        var goneBytes: Int64 = 0
        let fm = FileManager.default
        for (digest, bytes) in before.exclusiveDigestBytes {
            let blobPath = (root as NSString).appendingPathComponent("blobs/\(digest)")
            let alt = (root as NSString).appendingPathComponent("blobs/sha256-\(digest.replacingOccurrences(of: "sha256:", with: ""))")
            let exists = fm.fileExists(atPath: blobPath) || fm.fileExists(atPath: alt)
                || rebuilt.blobs.contains(where: { $0.digest == digest && $0.present })
            if exists {
                stillPresent += 1
            } else {
                goneBytes += bytes
            }
        }

        let freeAfter = StorageCapacityMeasurer.freeBytes()
        let diskDelta: Int64? = {
            guard let a = before.freeBytes, let b = freeAfter else { return nil }
            return b - a
        }()
        let mappedDelta: Int64? = present ? 0 : (before.uniqueBytes - remainingUnique)

        // Regeneration: model absent then present again within this observation window — not claimed here.
        let regen = false

        return AfterEvidence(
            modelPresent: present,
            inventoryFailure: inventory.failureReason,
            oldManifestPresent: fm.fileExists(atPath: before.manifestPath),
            remainingReferencedBlobCount: remainingRefs,
            remainingUniqueBytes: remainingUnique,
            remainingSharedBytes: remainingShared,
            exclusiveDigestsStillPresent: stillPresent,
            exclusiveDigestBytesGone: goneBytes,
            freeBytes: freeAfter,
            mappedDeltaBytes: mappedDelta,
            diskFreeDeltaBytes: diskDelta,
            regenerationDetected: regen,
            observedAt: Date()
        )
    }

    public static func verify(
        before: BeforeSnapshot,
        after: AfterEvidence,
        processFailed: Bool,
        contract: PostActionVerificationContract?
    ) -> OllamaPostMutationVerifier.Result {
        let modelStillInstalled = after.modelPresent
        let recovered: Int64? = {
            if modelStillInstalled || processFailed { return 0 }
            // Only post-state disappearance of exclusive digests counts.
            return after.exclusiveDigestBytesGone
        }()
        let remainingUnreferenced: Int64? = {
            if modelStillInstalled { return nil }
            if after.exclusiveDigestsStillPresent > 0 {
                return after.remainingUniqueBytes + after.remainingSharedBytes
            }
            return after.remainingUniqueBytes + after.remainingSharedBytes
        }()
        return OllamaPostMutationVerifier.verify(
            canonicalModel: before.canonicalModel,
            modelStillInstalled: modelStillInstalled,
            removedExclusiveBlobBytes: recovered,
            remainingUnreferencedBlobBytes: remainingUnreferenced,
            sharedRetainedBytes: after.remainingSharedBytes,
            contract: contract
        )
    }

    public static func recoveryStatus(from result: OllamaPostMutationVerifier.Result) -> String {
        result.storage.rawValue
    }

    private static func modelsRoot(from path: String) -> String {
        let std = (path as NSString).standardizingPath
        if let range = std.lowercased().range(of: "/.ollama/models") {
            let end = std.index(std.startIndex, offsetBy: std.distance(from: std.startIndex, to: range.upperBound))
            return String(std[..<end])
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/models")
    }

    private static func manifestPath(for canonical: String, itemPath: String) -> String {
        let std = (itemPath as NSString).standardizingPath
        if std.lowercased().contains("/manifests/") { return std }
        // library/qwen3:4b → manifests/registry.ollama.ai/library/qwen3/4b
        let parts = canonical.split(separator: "/")
        let nameTag: String
        let ns: String
        if parts.count == 2 {
            ns = String(parts[0])
            nameTag = String(parts[1])
        } else {
            ns = "library"
            nameTag = canonical
        }
        let name = nameTag.split(separator: ":").first.map(String.init) ?? nameTag
        let tag = nameTag.split(separator: ":").dropFirst().first.map(String.init) ?? "latest"
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent(".ollama/models/manifests/registry.ollama.ai/\(ns)/\(name)/\(tag)")
    }
}
