import Foundation

public struct AIToolDeepDetector: EntityDetector {
    public let domain = "AI Tools"
    public let bucket = SystemDataBucket.developer
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let specs: [(String, String, EntityKind, [String])] = [
            ("ai.cursor.cache", "\(home)/Library/Caches/Cursor", .cache, ["Cursor"]),
            ("ai.cursor.logs", "\(home)/Library/Application Support/Cursor/logs", .log, ["Cursor"]),
            ("ai.cursor.cached_data", "\(home)/Library/Application Support/Cursor/CachedData", .cache, ["Cursor"]),
            ("ai.cursor.gpu_cache", "\(home)/Library/Application Support/Cursor/GPUCache", .cache, ["Cursor"]),
            ("ai.cursor.code_cache", "\(home)/Library/Application Support/Cursor/Code Cache", .cache, ["Cursor"]),
            ("ai.cursor.user_settings", "\(home)/Library/Application Support/Cursor/User", .applicationSupport, ["Cursor"]),
            ("ai.cursor.workspace_storage", "\(home)/Library/Application Support/Cursor/User/workspaceStorage", .applicationSupport, ["Cursor"]),
            ("ai.cursor.history", "\(home)/Library/Application Support/Cursor/User/History", .log, ["Cursor"]),
            ("ai.cursor.global_storage", "\(home)/Library/Application Support/Cursor/User/globalStorage", .applicationSupport, ["Cursor"]),
            ("ai.cursor.extensions", "\(home)/Library/Application Support/Cursor/CachedExtensionVSIXs", .cache, ["Cursor"]),
            ("ai.cursor.indexeddb", "\(home)/Library/Application Support/Cursor/IndexedDB", .applicationSupport, ["Cursor"]),
            ("ai.claude.settings", "\(home)/.claude", .applicationSupport, []),
            ("ai.claude.projects", "\(home)/.claude/projects", .log, []),
            ("ai.claude.cache", "\(home)/.claude/cache", .cache, []),
            ("ai.claude.todos", "\(home)/.claude/todos", .applicationSupport, []),
            ("ai.codex.config", "\(home)/.codex", .applicationSupport, []),
            ("ai.codex.sessions", "\(home)/.codex/sessions", .log, []),
            ("ai.vscode.logs", "\(home)/Library/Application Support/Code/logs", .log, ["Code"]),
            ("ai.vscode.user", "\(home)/Library/Application Support/Code/User", .applicationSupport, ["Code"]),
            ("ai.vscode.cache", "\(home)/Library/Caches/com.microsoft.VSCode", .cache, ["Code"]),
            ("ai.ollama.models", "\(home)/.ollama/models", .cache, ["ollama"]),
            ("ai.ollama.blobs", "\(home)/.ollama/models/blobs", .cache, ["ollama"]),
            ("ai.ollama.manifests", "\(home)/.ollama/models/manifests", .cache, ["ollama"]),
            ("ai.ollama.logs", "\(home)/.ollama/logs", .log, ["ollama"]),
            ("ai.hf.hub", "\(home)/.cache/huggingface/hub", .cache, []),
            ("ai.hf.datasets", "\(home)/.cache/huggingface/datasets", .cache, []),
            ("ai.hf.root", "\(home)/.cache/huggingface", .cache, []),
            ("ai.lmstudio.models", "\(home)/.cache/lm-studio/models", .cache, []),
            ("ai.lmstudio.root", "\(home)/.cache/lm-studio", .cache, []),
        ]
        return specs.compactMap {
            node(id: $0.0, kind: $0.2, category: "AI_DEV", sub: $0.0, path: $0.1, scanner: scanner, bucket: bucket, domain: domain, processes: $0.3)
        } + semanticAIModelEntities(home: home, scanner: scanner)
    }

    /// Bounded exact vendor entity discovery under already-known roots — not a second home crawl.
    private func semanticAIModelEntities(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        _ = scanner
        var out: [DetectedEntity] = []
        let ollamaRoot = "\(home)/.ollama/models"
        if FileManager.default.fileExists(atPath: ollamaRoot) {
            let inventory = OllamaStorageProofProvider(processNames: ["ollama"]).prove(rootPath: ollamaRoot, budgetMs: 2_000)
            for entity in inventory.entities where entity.entityKind == .model {
                let storage = StorageEntity(
                    id: entity.entityID,
                    kind: .cache,
                    category: "AI_DEV",
                    subcategory: "ai.ollama.model",
                    displayName: entity.displayIdentity,
                    path: entity.canonicalPath,
                    logicalBytes: entity.logicalBytes
                )
                let annotation = DetectionAnnotation(
                    detectorID: "ollama.storage.proof",
                    specificity: 90,
                    semanticType: "OLLAMA_MODEL",
                    lifecycle: LifecycleEvidence(role: .model, roleConfidence: .verified, unknownReasons: []),
                    provenance: ProvenanceEvidence(
                        generatedByProduct: ProductIdentity(name: "Ollama", confidence: .verified),
                        storageRole: .model,
                        confidence: entity.provenanceConfidence,
                        unknownReasons: entity.isUserOriginalSuspect ? ["USER_ORIGINAL_OR_CUSTOM_MODEL_SUSPECT"] : []
                    ),
                    owningProducts: [ProductIdentity(name: "Ollama", confidence: .verified)],
                    unknownReasons: entity.topBlockers
                )
                out.append(DetectedEntity(
                    entity: storage,
                    bucket: bucket,
                    domain: domain,
                    associatedProcesses: ["ollama"],
                    identified: true,
                    annotation: annotation
                ))
            }
        }

        let hfHub = "\(home)/.cache/huggingface/hub"
        if FileManager.default.fileExists(atPath: hfHub) {
            let inventory = HuggingFaceStorageProofProvider().prove(rootPath: hfHub, budgetMs: 2_000)
            for entity in inventory.entities where entity.entityKind == .repository || entity.entityKind == .snapshot {
                let storage = StorageEntity(
                    id: entity.entityID,
                    kind: .cache,
                    category: "AI_DEV",
                    subcategory: entity.entityKind == .repository ? "ai.hf.repo" : "ai.hf.snapshot",
                    displayName: entity.displayIdentity,
                    path: entity.canonicalPath,
                    logicalBytes: entity.logicalBytes
                )
                let annotation = DetectionAnnotation(
                    detectorID: "huggingface.storage.proof",
                    specificity: 90,
                    semanticType: entity.entityKind == .repository ? "HF_REPOSITORY" : "HF_SNAPSHOT",
                    lifecycle: LifecycleEvidence(role: .model, roleConfidence: .verified, unknownReasons: []),
                    provenance: ProvenanceEvidence(
                        generatedByProduct: ProductIdentity(name: "Hugging Face", confidence: .verified),
                        storageRole: .model,
                        confidence: entity.provenanceConfidence,
                        unknownReasons: []
                    ),
                    owningProducts: [ProductIdentity(name: "Hugging Face", confidence: .verified)],
                    unknownReasons: entity.topBlockers
                )
                out.append(DetectedEntity(
                    entity: storage,
                    bucket: bucket,
                    domain: domain,
                    associatedProcesses: [],
                    identified: true,
                    annotation: annotation
                ))
            }
        }
        return out
    }
}

public struct ContainerDeepDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public var maxContainers: Int
    public init(maxContainers: Int = 15) {
        self.maxContainers = maxContainers
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Containers"
        let kids = ChildFolderEnumerator(maxChildren: maxContainers).immediateDirectories(at: root)
        var out: [DetectedEntity] = []
        for kid in kids {
            let bid = kid.name
            let product = BundleCatalog.product(for: bid)
            let domain = product.domain
            let pairs: [(String, String, EntityKind)] = [
                ("container.\(bid).documents", "\(kid.path)/Data/Documents", .userOriginal),
                ("container.\(bid).caches", "\(kid.path)/Data/Library/Caches", .cache),
                ("container.\(bid).preferences", "\(kid.path)/Data/Library/Preferences", .applicationSupport),
                ("container.\(bid).app_support", "\(kid.path)/Data/Library/Application Support", .applicationSupport),
                ("container.\(bid).tmp", "\(kid.path)/Data/tmp", .temp),
            ]
            for p in pairs {
                if let n = node(id: p.0, kind: p.2, category: "CONTAINER", sub: product.name, path: p.1, scanner: scanner, bucket: bucket, domain: domain, annotation: Self.annotation(id: p.0, bid: bid, kind: p.2)) {
                    out.append(n)
                }
            }
        }
        return out
    }

    static func annotation(id: String, bid: String, kind: EntityKind) -> DetectionAnnotation {
        let role: LifecycleRole
        let semantic: String
        switch kind {
        case .userOriginal:
            role = .userContent
            semantic = "CONTAINER_DOCUMENTS"
        case .cache:
            role = .cache
            semantic = "CONTAINER_CACHES"
        case .temp:
            role = .temporary
            semantic = "CONTAINER_TMP"
        case .applicationSupport:
            if id.contains(".preferences") {
                role = .userConfiguration
                semantic = "CONTAINER_PREFERENCES"
            } else {
                role = .mixed
                semantic = "CONTAINER_APP_SUPPORT"
            }
        default:
            role = .unknown
            semantic = "CONTAINER_UNKNOWN"
        }
        let identity = ProductIdentityResolver.resolve(bundleID: bid)
        var reasons: [String] = []
        if identity.confidence == .unknown { reasons.append(UnknownReasonCode.provenanceOwnerUnknown.rawValue) }
        return DetectionAnnotation(
            detectorID: "container.lifecycle",
            specificity: 80,
            semanticType: semantic,
            lifecycle: LifecycleEvidence(role: role, roleConfidence: .inferred, unknownReasons: [UnknownReasonCode.activeStateUnknown.rawValue]),
            provenance: ProvenanceEvidence(generatedByProduct: identity, bundleIdentifier: bid, storageRole: role, confidence: identity.confidence, unknownReasons: reasons),
            owningProducts: [identity],
            unknownReasons: reasons
        )
    }
}

public struct AppSupportDeepDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let products = ["Cursor", "Code", "Claude", "Google", "Slack", "Discord"]
        let root = "\(home)/Library/Application Support"
        var out: [DetectedEntity] = []
        for name in products {
            let base = "\(root)/\(name)"
            guard FileManager.default.fileExists(atPath: base) else { continue }
            let kids = ChildFolderEnumerator(maxChildren: 16).immediateDirectories(at: base)
            for kid in kids {
                let classified = LifecycleArtifactClassifier.classify(name: kid.name)
                let kind = classified.2 == .unknown ? Self.kind(for: kid.name) : classified.2
                let id = "appsupport.\(name).\(Self.slug(kid.name))"
                let note = DetectionAnnotation(
                    detectorID: "appsupport.lifecycle",
                    specificity: 55,
                    semanticType: classified.0.rawValue,
                    lifecycle: LifecycleEvidence(
                        role: classified.0,
                        roleConfidence: classified.1,
                        mixedContent: classified.0 == .unknown,
                        unknownReasons: classified.0 == .database ? [UnknownReasonCode.lifecycleDatabaseUnknown.rawValue] : []
                    ),
                    provenance: ProvenanceEvidence(
                        generatedByProduct: ProductIdentity(name: name, confidence: .inferred),
                        storageRole: classified.0,
                        confidence: .inferred,
                        unknownReasons: [UnknownReasonCode.sourceRelationUnknown.rawValue]
                    )
                )
                if let n = node(id: id, kind: kind, category: "APP_SUPPORT", sub: name, path: kid.path, scanner: scanner, bucket: bucket, domain: name == "Cursor" || name == "Code" || name == "Claude" ? "AI Tools" : "macOS", annotation: note) {
                    out.append(n)
                }
            }
        }
        return out
    }

    static func kind(for name: String) -> EntityKind {
        let n = name.lowercased()
        if n.contains("cache") || n.contains("log") { return n.contains("log") ? .log : .cache }
        if n.contains("pref") || n == "user" { return .applicationSupport }
        return .unknown
    }

    static func slug(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cache") { return "cache" }
        if n.contains("log") { return "logs" }
        if n.contains("workspace") { return "workspace" }
        if n.contains("history") { return "history" }
        if n.contains("extension") { return "extensions" }
        if n.contains("index") { return "index" }
        if n == "user" { return "user_settings" }
        if n.contains("global") { return "global_storage" }
        return name.replacingOccurrences(of: " ", with: "_")
    }
}

public enum BundleCatalog {
    public struct Product {
        public var name: String
        public var domain: String
    }

    public static func product(for bundleID: String) -> Product {
        let map: [String: Product] = [
            "com.tinyspeck.slackmacgap": Product(name: "Slack", domain: "macOS"),
            "com.microsoft.teams2": Product(name: "Microsoft Teams", domain: "macOS"),
            "com.google.Chrome": Product(name: "Chrome", domain: "macOS"),
            "com.openai.chat": Product(name: "ChatGPT", domain: "AI Tools"),
            "com.apple.MobileSMS": Product(name: "Messages", domain: "macOS"),
        ]
        if let hit = map[bundleID] { return hit }
        if bundleID.lowercased().contains("cursor") { return Product(name: "Cursor", domain: "AI Tools") }
        if bundleID.lowercased().contains("docker") { return Product(name: "Docker", domain: "Docker") }
        return Product(name: bundleID, domain: "macOS")
    }

    public static func known(_ bundleID: String) -> Product? {
        let map: [String: Product] = [
            "com.tinyspeck.slackmacgap": Product(name: "Slack", domain: "macOS"),
            "com.microsoft.teams2": Product(name: "Microsoft Teams", domain: "macOS"),
            "com.google.Chrome": Product(name: "Chrome", domain: "macOS"),
            "com.openai.chat": Product(name: "ChatGPT", domain: "AI Tools"),
            "com.apple.MobileSMS": Product(name: "Messages", domain: "macOS"),
        ]
        return map[bundleID]
    }
}
