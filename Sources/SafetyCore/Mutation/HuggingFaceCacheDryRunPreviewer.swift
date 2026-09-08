import Foundation

/// Read-only HF cache inventory + dry-run preview. Never mutates.
public enum HuggingFaceCacheDryRunPreviewer {
    public struct LocalRevisionInventory: Codable, Sendable, Equatable {
        public var cacheRoot: String
        public var repoID: String
        public var repoType: String
        public var revisions: [String]
        public var refs: [String: String]
        public var snapshotPresent: Bool
        public var targetRevision: String
        public var uniqueBytes: Int64?
        public var sharedBytes: Int64?
        public var exclusiveBlobCount: Int
        public var sharedBlobCount: Int
        public var fingerprint: String
        public var observedAt: Date
    }

    public static func resolveCacheRoot(from path: String) -> String {
        let std = (path as NSString).standardizingPath
        if let range = std.lowercased().range(of: "/huggingface/hub") {
            let end = std.index(std.startIndex, offsetBy: std.distance(from: std.startIndex, to: range.upperBound))
            return String(std[..<end])
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".cache/huggingface/hub")
    }

    public static func captureLocalInventory(
        repoID: String,
        revision: String,
        itemPath: String,
        uniqueBytes: Int64?,
        sharedBytes: Int64?,
        now: Date = Date()
    ) -> LocalRevisionInventory {
        let cacheRoot = resolveCacheRoot(from: itemPath)
        let repoDir = repoDirectory(cacheRoot: cacheRoot, repoID: repoID)
        let fm = FileManager.default
        let snapshotsDir = (repoDir as NSString).appendingPathComponent("snapshots")
        var revisions: [String] = []
        if let kids = try? fm.contentsOfDirectory(atPath: snapshotsDir) {
            revisions = kids.filter { HuggingFaceRevisionIdentity.isValidFullRevision($0) || $0.count >= 7 }.sorted()
        }
        var refs: [String: String] = [:]
        let refsDir = (repoDir as NSString).appendingPathComponent("refs")
        if let kids = try? fm.contentsOfDirectory(atPath: refsDir) {
            for name in kids {
                let p = (refsDir as NSString).appendingPathComponent(name)
                if let data = try? String(contentsOfFile: p, encoding: .utf8) {
                    refs[name] = data.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        let snap = (snapshotsDir as NSString).appendingPathComponent(revision)
        let present = fm.fileExists(atPath: snap)
        let exclusive = sharedBytes == 0 || sharedBytes == nil ? max(1, revisions.isEmpty ? 0 : 1) : 0
        let sharedCount = (sharedBytes ?? 0) > 0 ? 1 : 0
        let fp = ActionBindingFingerprintBuilder.stablePublicHash(
            [cacheRoot, repoID, revision, revisions.joined(separator: ","), "\(present)"].joined(separator: "|")
        )
        return LocalRevisionInventory(
            cacheRoot: cacheRoot,
            repoID: repoID,
            repoType: "model",
            revisions: revisions,
            refs: refs,
            snapshotPresent: present,
            targetRevision: revision,
            uniqueBytes: uniqueBytes,
            sharedBytes: sharedBytes,
            exclusiveBlobCount: exclusive,
            sharedBlobCount: sharedCount,
            fingerprint: fp,
            observedAt: now
        )
    }

    /// Execute vendor dry-run when CLI available. Otherwise synthesize conservative preview from local inventory.
    public static func preview(
        inventory: LocalRevisionInventory,
        interface: HuggingFaceNativeInterfaceResolution,
        processRunner: any BoundedProcessRunner = FoundationProcessRunner(),
        semanticExclusiveBlobCount: Int? = nil,
        semanticSharedBlobCount: Int? = nil
    ) -> HuggingFaceCacheRemovalPreview {
        let started = Date()
        let found = inventory.snapshotPresent || inventory.revisions.contains(where: {
            $0 == inventory.targetRevision || inventory.targetRevision.hasPrefix($0) || $0.hasPrefix(String(inventory.targetRevision.prefix(12)))
        })
        let revCount = max(inventory.revisions.count, found ? 1 : 0)
        let otherRetained = max(0, revCount - (found ? 1 : 0))
        let repoRemoval = found && revCount <= 1
        let refsAffected = inventory.refs.filter { $0.value == inventory.targetRevision || $0.value.hasPrefix(String(inventory.targetRevision.prefix(12))) }.map(\.key)

        var warnings: [String] = []
        var previewComplete = false
        var vendorFreed = inventory.uniqueBytes
        var rawDigest = "LOCAL_ONLY"
        var mutated = false

        if interface.executionTransportAvailable,
           let exePath = interface.cliExecutableURL,
           let args = try? HuggingFaceRevisionIdentity.rmArguments(
            revision: inventory.targetRevision,
            cacheRoot: inventory.cacheRoot,
            dryRun: true,
            yes: false
           ) {
            let result = processRunner.run(BoundedProcessRequest(
                executableURL: URL(fileURLWithPath: exePath),
                arguments: args,
                timeoutSeconds: 30
            ))
            let out = result.stdout + "\n" + result.stderr
            rawDigest = ActionBindingFingerprintBuilder.stablePublicHash(out)
            let parsed = parseDryRunOutput(out, target: inventory.targetRevision, revisionCount: revCount)
            if parsed.ambiguous {
                warnings.append("DRY_RUN_OUTPUT_AMBIGUOUS")
                previewComplete = false
            } else {
                previewComplete = parsed.complete && found
            }
            if let freed = parsed.freedBytes {
                vendorFreed = freed
            } else if let parsedSize = HuggingFaceDryRunSizeAgreement.parseVendorSizeToken(out) {
                vendorFreed = parsedSize
            }
            // Re-check inventory — dry-run must not mutate.
            let after = captureLocalInventory(
                repoID: inventory.repoID,
                revision: inventory.targetRevision,
                itemPath: inventory.cacheRoot + "/models--" + inventory.repoID.replacingOccurrences(of: "/", with: "--"),
                uniqueBytes: inventory.uniqueBytes,
                sharedBytes: inventory.sharedBytes
            )
            if after.snapshotPresent != inventory.snapshotPresent
                || Set(after.revisions) != Set(inventory.revisions)
                || after.refs != inventory.refs {
                mutated = true
                warnings.append("DRY_RUN_MUTATION_DETECTED")
                previewComplete = false
            }
            if result.outcome != .commandAccepted && result.outcome != .nonzeroExit {
                warnings.append("DRY_RUN_PROCESS_\(result.outcome.rawValue)")
                previewComplete = false
            }
        } else {
            warnings.append(interface.failureReason ?? "HF_CLI_UNAVAILABLE_FOR_DRY_RUN")
            // Without CLI, preview is incomplete — cannot claim vendor blast radius.
            previewComplete = false
        }

        let exclusive = semanticExclusiveBlobCount ?? inventory.exclusiveBlobCount
        let shared = semanticSharedBlobCount ?? inventory.sharedBlobCount
        return HuggingFaceCacheRemovalPreview(
            repoID: inventory.repoID,
            repoType: inventory.repoType,
            revision: inventory.targetRevision,
            cacheRoot: inventory.cacheRoot,
            revisionFound: found,
            revisionCountBefore: revCount,
            targetedRevisionCount: found ? 1 : 0,
            targetedSnapshotPaths: found
                ? [(repoDirectory(cacheRoot: inventory.cacheRoot, repoID: inventory.repoID) as NSString)
                    .appendingPathComponent("snapshots/\(inventory.targetRevision)")]
                : [],
            refEffects: refsAffected,
            exclusiveBlobCount: exclusive,
            sharedBlobCount: shared,
            expectedFreedBytesVendor: vendorFreed,
            expectedRepoDirectoryRemoval: repoRemoval,
            warnings: warnings + (otherRetained > 0 ? ["OTHER_REVISIONS_RETAINED=\(otherRetained)"] : []),
            previewComplete: previewComplete,
            rawOutputDigest: rawDigest,
            observedAt: Date(),
            dryRunMutationDetected: mutated,
            durationMs: Int(Date().timeIntervalSince(started) * 1000)
        )
    }

    private struct ParsedDryRun {
        var complete: Bool
        var ambiguous: Bool
        var freedBytes: Int64?
    }

    private static func parseDryRunOutput(_ text: String, target: String, revisionCount: Int) -> ParsedDryRun {
        let lower = text.lowercased()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ParsedDryRun(complete: false, ambiguous: true, freedBytes: nil)
        }
        let mentionsTarget = lower.contains(target.lowercased())
            || lower.contains(String(target.prefix(12)).lowercased())
        let looksLikeDry = lower.contains("dry")
            || lower.contains("would")
            || lower.contains("delete")
            || lower.contains("remove")
            || lower.contains("about to")
        let soleRepoLanguage = lower.contains("entire repo")
            || lower.contains("sole revision")
            || lower.contains("1 repo")
            || lower.contains("1 repo(s)")
        let freed = HuggingFaceDryRunSizeAgreement.parseVendorSizeToken(text)
            ?? {
                if let r = text.range(of: #"[0-9]+(\.[0-9]+)?\s*G(i)?B"#, options: .regularExpression) {
                    let num = String(text[r]).split(whereSeparator: { $0 == " " || $0 == "G" || $0 == "i" || $0 == "B" }).first.map(String.init)
                    if let n = num.flatMap(Double.init) { return Int64(n * 1_000_000_000) }
                }
                return nil
            }()

        // Argv already bound the exact revision. Vendor may summarize "entire repo (sole revision)"
        // without reprinting the hash — accept when local revisionCount == 1 and language agrees.
        if looksLikeDry && (mentionsTarget || (revisionCount == 1 && soleRepoLanguage) || (revisionCount == 1 && freed != nil)) {
            return ParsedDryRun(complete: true, ambiguous: false, freedBytes: freed)
        }
        if looksLikeDry && !mentionsTarget {
            return ParsedDryRun(complete: false, ambiguous: true, freedBytes: freed)
        }
        if !mentionsTarget && !looksLikeDry {
            return ParsedDryRun(complete: false, ambiguous: true, freedBytes: freed)
        }
        return ParsedDryRun(complete: mentionsTarget, ambiguous: false, freedBytes: freed)
    }

    private static func repoDirectory(cacheRoot: String, repoID: String) -> String {
        let encoded = "models--" + repoID.replacingOccurrences(of: "/", with: "--")
        return (cacheRoot as NSString).appendingPathComponent(encoded)
    }
}
