import Foundation

public protocol RemoteReacquisitionVerifier: Sendable {
    var vendor: VendorStorageKind { get }
    func verify(
        entity: VendorSemanticEntity,
        session: RemoteRequestSession
    ) -> RemoteReacquisitionProof
}

public struct HuggingFaceRemoteVerifier: RemoteReacquisitionVerifier {
    public let vendor: VendorStorageKind = .huggingFace
    public var hubHost: String

    public init(hubHost: String = "https://huggingface.co") {
        self.hubHost = hubHost
    }

    public func verify(entity: VendorSemanticEntity, session: RemoteRequestSession) -> RemoteReacquisitionProof {
        let now = Date()
        let freshUntil = now.addingTimeInterval(TimeInterval(session.freshnessSeconds))
        let redownload = entity.uniqueBytes ?? entity.logicalBytes

        guard entity.entityKind == .repository || entity.entityKind == .snapshot else {
            return RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entity.entityID,
                localIdentity: entity.displayIdentity,
                status: .notApplicable,
                freshUntil: freshUntil,
                authenticationClass: .unknown,
                proofMethod: .hfRevisionAPI,
                failureReason: "NOT_REVISION_SCOPED_ENTITY",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "huggingface.hub"
            )
        }

        guard let repo = entity.originIdentity, !repo.isEmpty else {
            return unknown(entity, session, reason: "LOCAL_ORIGIN_UNKNOWN", redownload: redownload)
        }
        // Exact immutable revision — never fall back to moving branch tip.
        let revision = entity.revisionIdentity
            ?? (entity.entityKind == .snapshot ? entity.displayIdentity.split(separator: "@").last.map(String.init) : nil)
        guard let revision, !revision.isEmpty else {
            return unknown(entity, session, reason: "LOCAL_REVISION_UNKNOWN", redownload: redownload)
        }

        // 1) Exact revision API — authoritative enough for identity + accessibility.
        guard let revURL = URL(string: "\(hubHost)/api/models/\(repo)/revision/\(revision)") else {
            return unknown(entity, session, reason: "REMOTE_URL_INVALID", redownload: redownload)
        }
        let revReq = RemoteHTTPRequest(
            method: "GET",
            url: revURL,
            cacheKey: "hf|rev|\(repo)|\(revision)"
        )
        let revResp = session.request(revReq, vendor: .huggingFace)
        let interpreted = interpret(status: revResp, entity: entity, repo: repo, revision: revision, session: session, redownload: redownload, method: .hfRevisionAPI, checked: 1)

        // Do not fall back to HEAD when the authoritative revision call already gave a decisive
        // non-success outcome (timeout/auth/rate-limit/identity/mismatch/5xx unknown).
        switch interpreted.status {
        case .verified, .authRequired, .identityMismatch, .timeout, .rateLimited:
            return interpreted
        case .unknown where revResp.timedOut || revResp.errorKind == "TIMEOUT" || revResp.errorKind == "NETWORK_ERROR" || revResp.errorKind == "REMOTE_BUDGET_EXCEEDED":
            return interpreted
        case .unknown where (500...599).contains(revResp.statusCode):
            return interpreted
        default:
            break
        }

        // 2) Bounded HEAD on one known small resolve path — never download full weights.
        if let headURL = URL(string: "\(hubHost)/\(repo)/resolve/\(revision)/config.json") {
            let headReq = RemoteHTTPRequest(
                method: "HEAD",
                url: headURL,
                cacheKey: "hf|head|\(repo)|\(revision)|config.json"
            )
            let headResp = session.request(headReq, vendor: .huggingFace)
            let headInterp = interpret(
                status: headResp,
                entity: entity,
                repo: repo,
                revision: revision,
                session: session,
                redownload: redownload,
                method: .hfResolveHEAD,
                checked: 2
            )
            if headInterp.status == .verified {
                return headInterp
            }
            if headInterp.status != .unknown {
                return headInterp
            }
        }
        return interpreted
    }

    private func interpret(
        status resp: RemoteHTTPResponse,
        entity: VendorSemanticEntity,
        repo: String,
        revision: String,
        session: RemoteRequestSession,
        redownload: Int64,
        method: RemoteProofMethod,
        checked: Int
    ) -> RemoteReacquisitionProof {
        let now = Date()
        let freshUntil = now.addingTimeInterval(TimeInterval(session.freshnessSeconds))
        if resp.timedOut || resp.errorKind == "TIMEOUT" {
            return RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entity.entityID,
                localIdentity: "\(repo)@\(revision)",
                remoteIdentity: repo,
                remoteRevisionOrDigest: revision,
                status: .timeout,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: method,
                requiredObjectsChecked: checked,
                requiredObjectsVerified: 0,
                failureReason: "TIMEOUT",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "huggingface.hub"
            )
        }
        if resp.errorKind == "REMOTE_BUDGET_EXCEEDED" || resp.errorKind == "NETWORK_ERROR" {
            return unknown(entity, session, reason: resp.errorKind ?? "NETWORK_ERROR", redownload: redownload, revision: revision, repo: repo)
        }
        switch resp.statusCode {
        case 200:
            // Ensure body (if any) does not contradict revision identity when JSON present.
            if !resp.body.isEmpty,
               let json = try? JSONSerialization.jsonObject(with: resp.body) as? [String: Any] {
                if let sha = (json["sha"] as? String) ?? (json["commitId"] as? String) ?? (json["id"] as? String),
                   !sha.isEmpty,
                   !revision.hasPrefix(String(sha.prefix(min(7, sha.count)))) && sha != revision && !sha.hasPrefix(revision) {
                    // Some APIs return full sha; local may be abbreviated — allow prefix match either way.
                    if !sha.hasPrefix(revision) && !revision.hasPrefix(String(sha.prefix(12))) {
                        return RemoteReacquisitionProof(
                            vendor: .huggingFace,
                            entityID: entity.entityID,
                            localIdentity: "\(repo)@\(revision)",
                            remoteIdentity: repo,
                            remoteRevisionOrDigest: sha,
                            status: .identityMismatch,
                            freshUntil: freshUntil,
                            authenticationClass: .anonymous,
                            proofMethod: method,
                            requiredObjectsChecked: checked,
                            requiredObjectsVerified: 0,
                            failureReason: "REVISION_MISMATCH",
                            confidence: .verified,
                            estimatedRedownloadBytes: redownload,
                            endpointClass: "huggingface.hub"
                        )
                    }
                }
            }
            return RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entity.entityID,
                localIdentity: "\(repo)@\(revision)",
                remoteIdentity: repo,
                remoteRevisionOrDigest: revision,
                status: .verified,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: method,
                requiredObjectsChecked: checked,
                requiredObjectsVerified: checked,
                confidence: .verified,
                estimatedRedownloadBytes: redownload,
                endpointClass: "huggingface.hub"
            )
        case 401, 403:
            return RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entity.entityID,
                localIdentity: "\(repo)@\(revision)",
                remoteIdentity: repo,
                remoteRevisionOrDigest: revision,
                status: .authRequired,
                freshUntil: freshUntil,
                authenticationClass: .authRequired,
                proofMethod: method,
                requiredObjectsChecked: checked,
                requiredObjectsVerified: 0,
                failureReason: "AUTH_OR_GATED",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "huggingface.hub"
            )
        case 404:
            // Exact revision missing — do NOT claim latest is acceptable.
            return RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entity.entityID,
                localIdentity: "\(repo)@\(revision)",
                remoteIdentity: repo,
                remoteRevisionOrDigest: revision,
                status: .identityMismatch,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: method,
                requiredObjectsChecked: checked,
                requiredObjectsVerified: 0,
                failureReason: "EXACT_REVISION_NOT_FOUND",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "huggingface.hub"
            )
        case 429:
            return RemoteReacquisitionProof(
                vendor: .huggingFace,
                entityID: entity.entityID,
                localIdentity: "\(repo)@\(revision)",
                remoteIdentity: repo,
                remoteRevisionOrDigest: revision,
                status: .rateLimited,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: method,
                requiredObjectsChecked: checked,
                requiredObjectsVerified: 0,
                failureReason: "RATE_LIMITED",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "huggingface.hub"
            )
        case 500...599:
            return unknown(entity, session, reason: "REMOTE_5XX", redownload: redownload, revision: revision, repo: repo)
        default:
            return unknown(entity, session, reason: "HTTP_\(resp.statusCode)", redownload: redownload, revision: revision, repo: repo)
        }
    }

    private func unknown(
        _ entity: VendorSemanticEntity,
        _ session: RemoteRequestSession,
        reason: String,
        redownload: Int64,
        revision: String? = nil,
        repo: String? = nil
    ) -> RemoteReacquisitionProof {
        RemoteReacquisitionProof(
            vendor: .huggingFace,
            entityID: entity.entityID,
            localIdentity: entity.displayIdentity,
            remoteIdentity: repo,
            remoteRevisionOrDigest: revision,
            status: .unknown,
            freshUntil: Date().addingTimeInterval(TimeInterval(session.freshnessSeconds)),
            authenticationClass: .unknown,
            proofMethod: .hfRevisionAPI,
            failureReason: reason,
            confidence: .unknown,
            estimatedRedownloadBytes: redownload,
            endpointClass: "huggingface.hub"
        )
    }
}

public struct OllamaRemoteVerifier: RemoteReacquisitionVerifier {
    public let vendor: VendorStorageKind = .ollama
    public var registryHost: String

    public init(registryHost: String = "https://registry.ollama.ai") {
        self.registryHost = registryHost
    }

    public func verify(entity: VendorSemanticEntity, session: RemoteRequestSession) -> RemoteReacquisitionProof {
        let freshUntil = Date().addingTimeInterval(TimeInterval(session.freshnessSeconds))
        let redownload = entity.uniqueBytes ?? entity.logicalBytes

        guard entity.entityKind == .model else {
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: entity.displayIdentity,
                status: .notApplicable,
                freshUntil: freshUntil,
                authenticationClass: .unknown,
                proofMethod: .ollamaManifestGET,
                failureReason: "NOT_MODEL_ENTITY",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }

        if entity.isUserOriginalSuspect || entity.originIdentity == "local" {
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: entity.displayIdentity,
                status: .notApplicable,
                freshUntil: freshUntil,
                authenticationClass: .unknown,
                proofMethod: .ollamaManifestGET,
                failureReason: "CUSTOM_OR_LOCAL_NO_REMOTE_ORIGIN",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }

        // displayIdentity like library/qwen3:4b ; path .../manifests/registry.ollama.ai/library/qwen3/4b
        let (namespace, model, tag) = parseModelIdentity(entity)
        guard let namespace, let model, let tag else {
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: entity.displayIdentity,
                status: .unknown,
                freshUntil: freshUntil,
                authenticationClass: .unknown,
                proofMethod: .ollamaManifestGET,
                failureReason: "MODEL_IDENTITY_UNPARSABLE",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }

        guard let url = URL(string: "\(registryHost)/v2/\(namespace)/\(model)/manifests/\(tag)") else {
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: entity.displayIdentity,
                status: .unknown,
                freshUntil: freshUntil,
                authenticationClass: .unknown,
                proofMethod: .ollamaManifestGET,
                failureReason: "REMOTE_URL_INVALID",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }

        let req = RemoteHTTPRequest(
            method: "GET",
            url: url,
            headers: ["Accept": "application/vnd.docker.distribution.manifest.v2+json"],
            cacheKey: "ollama|manifest|\(namespace)|\(model)|\(tag)"
        )
        let resp = session.request(req, vendor: .ollama)
        return interpretManifest(
            resp: resp,
            entity: entity,
            namespace: namespace,
            model: model,
            tag: tag,
            session: session,
            redownload: redownload
        )
    }

    private func interpretManifest(
        resp: RemoteHTTPResponse,
        entity: VendorSemanticEntity,
        namespace: String,
        model: String,
        tag: String,
        session: RemoteRequestSession,
        redownload: Int64
    ) -> RemoteReacquisitionProof {
        let freshUntil = Date().addingTimeInterval(TimeInterval(session.freshnessSeconds))
        let identity = "\(namespace)/\(model):\(tag)"
        if resp.timedOut || resp.errorKind == "TIMEOUT" {
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .timeout,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                failureReason: "TIMEOUT",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }
        if resp.errorKind == "REMOTE_BUDGET_EXCEEDED" || resp.errorKind == "NETWORK_ERROR" {
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .unknown,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                failureReason: resp.errorKind,
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }
        switch resp.statusCode {
        case 200:
            guard let remote = parseDigests(from: resp.body) else {
                return RemoteReacquisitionProof(
                    vendor: .ollama,
                    entityID: entity.entityID,
                    localIdentity: identity,
                    remoteIdentity: identity,
                    status: .unknown,
                    freshUntil: freshUntil,
                    authenticationClass: .anonymous,
                    proofMethod: .ollamaManifestGET,
                    requiredObjectsChecked: 1,
                    requiredObjectsVerified: 0,
                    failureReason: "MANIFEST_UNPARSEABLE",
                    confidence: .unknown,
                    estimatedRedownloadBytes: redownload,
                    endpointClass: "ollama.registry"
                )
            }
            let local = Set(entity.referencedBlobDigests.map(normalizeDigest))
            let remoteSet = Set(remote.map(normalizeDigest))
            // Mutable tag drift: tag resolves but digests differ from installed exact model.
            if !local.isEmpty, local != remoteSet {
                return RemoteReacquisitionProof(
                    vendor: .ollama,
                    entityID: entity.entityID,
                    localIdentity: identity,
                    remoteIdentity: identity,
                    remoteRevisionOrDigest: remote.sorted().joined(separator: ","),
                    status: .identityMismatch,
                    freshUntil: freshUntil,
                    authenticationClass: .anonymous,
                    proofMethod: .ollamaManifestGET,
                    requiredObjectsChecked: local.count,
                    requiredObjectsVerified: local.intersection(remoteSet).count,
                    failureReason: "TAG_POINTS_TO_DIFFERENT_MANIFEST",
                    confidence: .verified,
                    estimatedRedownloadBytes: redownload,
                    endpointClass: "ollama.registry"
                )
            }
            let verifiedCount = local.isEmpty ? remoteSet.count : local.intersection(remoteSet).count
            let checked = max(local.count, remoteSet.count)
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                remoteRevisionOrDigest: remote.sorted().joined(separator: ","),
                status: .verified,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                requiredObjectsChecked: checked,
                requiredObjectsVerified: verifiedCount,
                confidence: .verified,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        case 401, 403:
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .authRequired,
                freshUntil: freshUntil,
                authenticationClass: .authRequired,
                proofMethod: .ollamaManifestGET,
                failureReason: "AUTH_REQUIRED",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        case 404:
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .identityMismatch,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                failureReason: "EXACT_MANIFEST_NOT_FOUND",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        case 429:
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .rateLimited,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                failureReason: "RATE_LIMITED",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        case 500...599:
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .unknown,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                failureReason: "REMOTE_5XX",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        default:
            return RemoteReacquisitionProof(
                vendor: .ollama,
                entityID: entity.entityID,
                localIdentity: identity,
                remoteIdentity: identity,
                status: .unknown,
                freshUntil: freshUntil,
                authenticationClass: .anonymous,
                proofMethod: .ollamaManifestGET,
                failureReason: "HTTP_\(resp.statusCode)",
                confidence: .unknown,
                estimatedRedownloadBytes: redownload,
                endpointClass: "ollama.registry"
            )
        }
    }

    private func parseModelIdentity(_ entity: VendorSemanticEntity) -> (String?, String?, String?) {
        // Prefer path: .../manifests/registry.ollama.ai/library/qwen3/4b
        let path = entity.canonicalPath
        if let range = path.range(of: "/manifests/") {
            let rest = String(path[range.upperBound...]).split(separator: "/")
            // registry / namespace / model / tag  OR registry / library / model / tag
            if rest.count >= 4 {
                let namespace = String(rest[rest.count - 3])
                let model = String(rest[rest.count - 2])
                let tag = String(rest[rest.count - 1])
                return (namespace, model, tag)
            }
        }
        // display: library/qwen3:4b
        let parts = entity.displayIdentity.split(separator: ":")
        guard parts.count == 2 else { return (nil, nil, nil) }
        let nameParts = parts[0].split(separator: "/")
        guard nameParts.count >= 2 else { return (nil, nil, nil) }
        return (String(nameParts[nameParts.count - 2]), String(nameParts[nameParts.count - 1]), String(parts[1]))
    }

    private func parseDigests(from data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var digests: [String] = []
        if let config = json["config"] as? [String: Any], let d = config["digest"] as? String {
            digests.append(d)
        }
        if let layers = json["layers"] as? [[String: Any]] {
            for layer in layers {
                if let d = layer["digest"] as? String { digests.append(d) }
            }
        }
        return digests.isEmpty ? nil : digests
    }

    private func normalizeDigest(_ raw: String) -> String {
        var d = raw.lowercased()
        if d.hasPrefix("sha256:") { d = "sha256-" + d.dropFirst("sha256:".count) }
        return d
    }
}

/// Late-stage remote proof orchestrator. Does not assign SafetyClass. Does not mutate storage.
public enum RemoteReacquisitionService {
    public static func proveAll(
        inventories: [VendorProofInventory],
        session: RemoteRequestSession = RemoteRequestSession(),
        hf: RemoteReacquisitionVerifier = HuggingFaceRemoteVerifier(),
        ollama: RemoteReacquisitionVerifier = OllamaRemoteVerifier()
    ) -> (proofs: [RemoteReacquisitionProof], session: RemoteRequestSession) {
        var proofs: [RemoteReacquisitionProof] = []
        for inv in inventories {
            let verifier: RemoteReacquisitionVerifier = inv.vendor == .huggingFace ? hf : ollama
            let targets = inv.entities.filter { e in
                switch e.entityKind {
                case .model:
                    return true
                case .snapshot:
                    return true
                case .repository:
                    // Prefer exact snapshot/revision entities; avoid double-counting repo+snapshot.
                    let hasSnapshot = inv.entities.contains {
                        $0.entityKind == .snapshot && $0.originIdentity == e.originIdentity
                    }
                    return !hasSnapshot
                default:
                    return false
                }
            }
            for entity in targets {
                if session.isBudgetExhausted { break }
                // Prefer snapshot over repo for HF when both exist; still verify both within budget.
                let proof = verifier.verify(entity: entity, session: session)
                RemoteReacquisitionProofIndex.store(proof)
                proofs.append(proof)
            }
        }
        return (proofs, session)
    }

    public static func apply(proof: RemoteReacquisitionProof, to verification: inout VerificationAnnotation) {
        verification.remoteReacquisitionProof = proof
        verification.estimatedRedownloadBytes = proof.estimatedRedownloadBytes
        switch proof.status {
        case .verified where proof.isFresh:
            verification.reacquisition = ObservationRecord(
                value: .true,
                confidence: .verified,
                completeness: .complete,
                source: .vendorRule,
                reasonCode: "REMOTE_REACQUIRABLE_VERIFIED"
            )
            verification.vendorProofNotes.append("REMOTE_REACQUISITION_VERIFIED")
            verification.vendorProofNotes.append("FRESH_UNTIL=\(Int(proof.freshUntil.timeIntervalSince1970))")
            verification.unknownReasons.removeAll { $0 == "REACQUISITION_REMOTE_UNKNOWN" }
            if !verification.vendorProofNotes.contains("VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE") {
                verification.vendorProofNotes.append("VENDOR_NATIVE_CLEANUP_EXECUTOR_UNAVAILABLE")
            }
        case .identityMismatch:
            verification.reacquisition = ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .vendorRule,
                reasonCode: proof.failureReason ?? "REMOTE_IDENTITY_MISMATCH"
            )
            verification.vendorProofNotes.append("REMOTE_IDENTITY_MISMATCH")
        case .authRequired:
            verification.reacquisition = ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .vendorRule,
                reasonCode: "AUTH_REQUIRED"
            )
            verification.vendorProofNotes.append("AUTH_REQUIRED")
        case .timeout, .rateLimited, .remoteUnavailable, .accessUnknown, .unknown, .conflicted, .notApplicable:
            verification.reacquisition = ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .vendorRule,
                reasonCode: proof.failureReason ?? proof.status.rawValue
            )
            verification.vendorProofNotes.append(proof.status.rawValue)
        case .verified:
            // Stale verified must not satisfy strict predicate.
            verification.reacquisition = ObservationRecord(
                value: .unknown,
                confidence: .unknown,
                completeness: .partial,
                source: .vendorRule,
                reasonCode: "REMOTE_PROOF_STALE"
            )
            verification.vendorProofNotes.append("REMOTE_PROOF_STALE")
        }
    }
}
