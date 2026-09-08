import Foundation

public enum ActionPolicy {
    public static let userOwnedRoots = ["Desktop", "Documents", "Downloads"]

    public static func actionMode(for action: StorageAction) -> ActionMode? {
        switch action {
        case .keep: return .noAction
        case .moveToTrash: return .moveToTrash
        case .moveToICloud: return nil
        case .removeLocalDownload: return .cloudEvictOnly
        case .vendorNativeCleanup: return .toolCLIOnly
        }
    }

    public static func isVoiceMemo(_ item: ClassifiedItem) -> Bool {
        let id = item.detected.entity.id.lowercased()
        let path = item.detected.entity.path.lowercased()
        return id.hasPrefix("voicememos") || path.contains("voicememos") || path.contains("com.apple.voicememos")
    }

    public static func isIOSBackup(_ item: ClassifiedItem) -> Bool {
        let id = item.detected.entity.id.lowercased()
        let path = item.detected.entity.path.lowercased()
        return id.hasPrefix("ios.backup") || path.contains("mobilesync/backup")
    }

    public static func isClaudeRuntime(_ item: ClassifiedItem) -> Bool {
        item.detected.entity.id.lowercased().contains("claude.vm")
            || item.detected.entity.path.lowercased().contains("rootfs.img")
    }

    public static func isDerivedData(_ item: ClassifiedItem) -> Bool {
        item.detected.entity.path.lowercased().contains("deriveddata")
            || item.detected.entity.id.lowercased().contains("deriveddata")
    }

    public static func isOllamaStorage(_ item: ClassifiedItem) -> Bool {
        isOllamaStorage(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func isOllamaStorage(entityID: String, path: String) -> Bool {
        let id = entityID.lowercased()
        let p = path.lowercased()
        return id.contains("ollama") || p.contains("/.ollama/")
    }

    public static func isHuggingFaceStorage(_ item: ClassifiedItem) -> Bool {
        isHuggingFaceStorage(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func isHuggingFaceStorage(entityID: String, path: String) -> Bool {
        let id = entityID.lowercased()
        let p = path.lowercased()
        return id.contains("ai.hf") || id.contains("huggingface") || p.contains("/huggingface/")
    }

    public static func isAIVendorModelStorage(_ item: ClassifiedItem) -> Bool {
        isOllamaStorage(item) || isHuggingFaceStorage(item)
    }

    public static func isRawAIVendorBlob(_ item: ClassifiedItem) -> Bool {
        isRawAIVendorBlob(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func isRawAIVendorBlob(entityID: String, path: String) -> Bool {
        let id = entityID.lowercased()
        let p = path.lowercased()
        if id.contains("ollama.blobs") || (p.hasSuffix("/blobs") && (p.contains("/.ollama/") || p.contains("/huggingface/"))) {
            return true
        }
        if id.contains("ai.ollama.blob") || id.contains("ai.hf.blob") { return true }
        return false
    }

    public static func isOllamaModelEntity(_ item: ClassifiedItem) -> Bool {
        isOllamaModelEntity(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func isOllamaModelEntity(entityID: String, path: String) -> Bool {
        let id = entityID.lowercased()
        guard isOllamaStorage(entityID: entityID, path: path) else { return false }
        if isRawAIVendorBlob(entityID: entityID, path: path) { return false }
        if id == "ai.ollama.models" || id.hasSuffix(".models") && id.contains("ollama") { return false }
        return id.contains("ai.ollama.model.") || id.contains("ollama.model")
    }

    /// Exact HF hub snapshot / revision entity — not repo root, hub root, or blob.
    public static func isHuggingFaceSnapshotEntity(_ item: ClassifiedItem) -> Bool {
        isHuggingFaceSnapshotEntity(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func isHuggingFaceSnapshotEntity(entityID: String, path: String) -> Bool {
        guard isHuggingFaceStorage(entityID: entityID, path: path) else { return false }
        guard !isRawAIVendorBlob(entityID: entityID, path: path) else { return false }
        let id = entityID.lowercased()
        let p = path.lowercased()
        if id.contains("ai.hf.hub") || id.contains("ai.hf.root") || id.contains("ai.hf.datasets") { return false }
        if id.contains("ai.hf.repo.") && !id.contains("snapshot") && !p.contains("/snapshots/") { return false }
        if id.contains("ai.hf.snapshot") { return true }
        if p.contains("/snapshots/") {
            let rev = (path as NSString).lastPathComponent
            return HuggingFaceRevisionIdentity.isValidFullRevision(rev) || rev.count >= 12
        }
        return vendorEntityKind(entityID: entityID, path: path) == .snapshot
    }

    /// Full immutable revision hash for HF snapshot entity.
    public static func huggingFaceRevision(from item: ClassifiedItem) -> String? {
        let path = item.detected.entity.path
        let last = (path as NSString).lastPathComponent
        if HuggingFaceRevisionIdentity.isValidFullRevision(last) { return last.lowercased() }
        if let note = item.verification?.vendorProofNotes.first(where: { $0.hasPrefix("HF_REVISION=") }) {
            let rev = String(note.dropFirst("HF_REVISION=".count))
            if HuggingFaceRevisionIdentity.isValidFullRevision(rev) { return rev.lowercased() }
        }
        if let origin = item.verification?.reconstructionMechanism,
           let at = origin.split(separator: "@").last.map(String.init),
           HuggingFaceRevisionIdentity.isValidFullRevision(at) {
            return at.lowercased()
        }
        // Resolve short prefix from entity id against local snapshots dir.
        if path.lowercased().contains("/snapshots/") {
            let parent = (path as NSString).deletingLastPathComponent
            if let kids = try? FileManager.default.contentsOfDirectory(atPath: parent) {
                let matches = kids.filter { HuggingFaceRevisionIdentity.isValidFullRevision($0) }
                if matches.count == 1 { return matches[0].lowercased() }
                if matches.contains(where: { $0.lowercased() == last.lowercased() }) {
                    return last.lowercased()
                }
            }
        }
        return nil
    }

    public static func huggingFaceRepoID(from item: ClassifiedItem) -> String? {
        let path = item.detected.entity.path
        let parts = path.components(separatedBy: "/")
        if let folder = parts.first(where: { $0.hasPrefix("models--") }) {
            let rest = folder.replacingOccurrences(of: "models--", with: "")
            return rest.replacingOccurrences(of: "--", with: "/")
        }
        let id = item.detected.entity.id
        if id.hasPrefix("ai.hf.snapshot.") {
            var rest = String(id.dropFirst("ai.hf.snapshot.".count))
            // strip trailing .shortRev
            if let lastDot = rest.lastIndex(of: ".") {
                let maybeRev = String(rest[rest.index(after: lastDot)...])
                if maybeRev.count >= 7, maybeRev.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
                    rest = String(rest[..<lastDot])
                }
            }
            let comps = rest.split(separator: ".")
            if comps.count >= 2 {
                return "\(comps[0])/\(comps.dropFirst().joined(separator: "."))"
            }
        }
        return item.detected.entity.displayName.split(separator: "@").first.map(String.init)
    }

    public static func vendorStorageKind(_ item: ClassifiedItem) -> VendorStorageKind? {
        vendorStorageKind(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func vendorStorageKind(entityID: String, path: String) -> VendorStorageKind? {
        if isOllamaStorage(entityID: entityID, path: path) { return .ollama }
        if isHuggingFaceStorage(entityID: entityID, path: path) { return .huggingFace }
        return nil
    }

    public static func vendorEntityKind(_ item: ClassifiedItem) -> VendorEntityKind? {
        vendorEntityKind(entityID: item.detected.entity.id, path: item.detected.entity.path)
    }

    public static func vendorEntityKind(entityID: String, path: String) -> VendorEntityKind? {
        let id = entityID.lowercased()
        let p = path.lowercased()
        if isRawAIVendorBlob(entityID: entityID, path: path) { return .blob }
        if isOllamaModelEntity(entityID: entityID, path: path) { return .model }
        if id.contains("ai.ollama.models") { return .modelsRoot }
        if id.contains("snapshot") || p.contains("/snapshots/") { return .snapshot }
        if id.contains("ai.hf.repo") || (isHuggingFaceStorage(entityID: entityID, path: path) && p.contains("models--")) {
            return .repository
        }
        if isHuggingFaceStorage(entityID: entityID, path: path) { return .hubRoot }
        if isOllamaStorage(entityID: entityID, path: path) { return .unknownLocal }
        return nil
    }

    /// Display identity for Ollama model entities: `library/qwen3:4b`
    public static func ollamaCanonicalModelName(from item: ClassifiedItem) -> String? {
        guard isOllamaModelEntity(item) else { return nil }
        let display = item.detected.entity.displayName
        if OllamaModelIdentity.isValidCanonical(display) { return display }
        // Recover from entity id: ai.ollama.model.library.qwen3:4b
        let id = item.detected.entity.id
        if let range = id.range(of: "ai.ollama.model.") {
            let rest = String(id[range.upperBound...])
            // library.qwen3:4b → library/qwen3:4b (only first namespace slash)
            if let colon = rest.firstIndex(of: ":") {
                let namePart = String(rest[..<colon])
                let tag = String(rest[rest.index(after: colon)...])
                let parts = namePart.split(separator: ".").map(String.init)
                let reconstructed: String
                if parts.count >= 2 {
                    reconstructed = "\(parts[0])/\(parts.dropFirst().joined(separator: ".")):\(tag)"
                } else {
                    reconstructed = "\(namePart):\(tag)"
                }
                if OllamaModelIdentity.isValidCanonical(reconstructed) { return reconstructed }
            }
        }
        return nil
    }

    public static func isLibraryManagedPath(_ path: String) -> Bool {
        let expanded = PathGlob.expandHome(path)
        let lower = expanded.lowercased()
        if lower.contains("/library/applicationsupport") || lower.contains("/library/application support") { return true }
        if lower.contains("/library/containers") { return true }
        if lower.contains("/library/group containers") { return true }
        if lower.contains("/library/caches") { return true }
        if lower.contains("/library/developer") { return true }
        if lower.contains("globalstorage") || lower.contains("/snapshots/") { return true }
        if lower.contains("node_modules") { return true }
        if lower.contains(".vm") || lower.contains("rootfs.img") { return true }
        return false
    }

    public static func isGitRepository(_ item: ClassifiedItem) -> Bool {
        let path = item.detected.entity.path.lowercased()
        let id = item.detected.entity.id.lowercased()
        if id.hasPrefix("git.") { return true }
        if path.contains("/.git") || path.hasSuffix(".git") { return true }
        if item.detected.entity.kind == .gitHistory || item.detected.entity.kind == .gitMetadata { return true }
        return false
    }

    public static func isUserOwnedRoot(_ path: String) -> Bool {
        let expanded = PathGlob.expandHome(path)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for root in userOwnedRoots {
            let prefix = (home as NSString).appendingPathComponent(root)
            if expanded == prefix || expanded.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    public static func userOwnedVerified(_ item: ClassifiedItem) -> Bool {
        let role = item.detected.annotation?.lifecycle.role
        if role == .userContent || role == .download { return true }
        if item.verification?.sourceOfTruth.value == .true, item.verification?.sourceOfTruth.confidence == .verified {
            return true
        }
        return isUserOwnedRoot(item.detected.entity.path)
    }

    public static func fileProviderBacked(_ item: ClassifiedItem, evidence: EvidenceBundle?) -> Bool {
        item.detected.bucket == .cloud
            || item.detected.entity.kind == .cloudPlaceholder
            || item.detected.entity.kind == .cloudLocalMaterialized
            || evidence?.cloudFileProvider == .true
    }
}
