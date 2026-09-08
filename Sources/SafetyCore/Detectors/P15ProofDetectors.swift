import Foundation

/// P1.5/P1.6 detectors: DerivedData lightweight proof, node_modules opt-in proof, Chrome split, TomyLocal.
public struct XcodeDerivedDataProofDetector: EntityDetector {
    public let domain = "Xcode"
    public let bucket = SystemDataBucket.developer
    public var tier: DetectorTier { .optInProof }
    public var maxChildren: Int
    /// Soft budget: max metadata files inspected per instance (info.plist + markers).
    public var maxMetadataFilesPerEntity: Int
    public init(maxChildren: Int = 6, maxMetadataFilesPerEntity: Int = 4) {
        self.maxChildren = maxChildren
        self.maxMetadataFilesPerEntity = maxMetadataFilesPerEntity
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Developer/Xcode/DerivedData"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let xcode = ProductIdentity(name: "Xcode", confidence: .verified)
        let skip: Set<String> = ["ModuleCache.noindex", "SourcePackages", "CompilationCache.noindex", "SymbolCache.noindex"]

        for child in ChildFolderEnumerator(maxChildren: maxChildren).immediateDirectories(at: root) {
            if skip.contains(child.name) { continue }
            let started = Date()
            let infoPath = "\(child.path)/info.plist"
            var filesInspected = 0
            var workspacePath: String?
            if FileManager.default.fileExists(atPath: infoPath), filesInspected < maxMetadataFilesPerEntity {
                filesInspected += 1
                workspacePath = Self.readWorkspacePath(infoPath)
            }
            var rels: [EntityRelationship] = [
                EntityRelationship(type: .generatedBy, target: "Xcode", presence: .present, confidence: .verified)
            ]
            var reasons: [String] = []
            var conf: EvidenceConfidence = .inferred
            var relatedSource: String?

            if let workspacePath {
                let exists = FileManager.default.fileExists(atPath: workspacePath)
                rels.append(EntityRelationship(
                    type: .derivedFrom,
                    target: workspacePath,
                    presence: exists ? .present : .missing,
                    confidence: .verified
                ))
                rels.append(EntityRelationship(
                    type: .belongsToWorkspace,
                    target: workspacePath,
                    presence: exists ? .present : .missing,
                    confidence: .verified
                ))
                relatedSource = workspacePath
                conf = exists ? .verified : .inferred
                if !exists { reasons.append(UnknownReasonCode.workspaceReferenceMissing.rawValue) }
            } else {
                reasons.append(UnknownReasonCode.sourceRelationUnknown.rawValue)
            }

            let proofRuntimeMs = Int(Date().timeIntervalSince(started) * 1000)
            var note = DetectionAnnotation(
                detectorID: "xcode.deriveddata.proof",
                specificity: 120,
                semanticType: "XCODE_DERIVEDDATA_INSTANCE",
                lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .verified),
                provenance: ProvenanceEvidence(
                    generatedByProduct: xcode,
                    relatedWorkspace: relatedSource,
                    relatedManifest: FileManager.default.fileExists(atPath: infoPath) ? infoPath : nil,
                    relatedSource: relatedSource,
                    creationMechanism: "xcodebuild",
                    storageRole: .generatedArtifact,
                    confidence: conf,
                    unknownReasons: reasons
                ),
                relationships: rels,
                unknownReasons: reasons
            )
            // Attach lightweight proof budget into unknownReasons as structured tags (report layer parses).
            note.unknownReasons.append("PROOF_BUDGET_FILES=\(filesInspected)/\(maxMetadataFilesPerEntity)")
            note.unknownReasons.append("PROOF_RUNTIME_MS=\(proofRuntimeMs)")
            if let n = lightweightNode(
                id: "xcode.deriveddata.\(Self.slug(child.name))",
                kind: .generatedBuild,
                category: "DEVELOPER",
                sub: "DerivedData",
                path: child.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                processes: ["Xcode", "xcodebuild"],
                annotation: note
            ) { out.append(n) }
        }
        return out
    }

    public static func readWorkspacePath(_ infoPlist: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlist)),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return obj["WorkspacePath"] as? String
    }

    static func slug(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}

public struct NodeModulesProofDetector: EntityDetector {
    public let domain = "Node"
    public let bucket = SystemDataBucket.developer
    public var tier: DetectorTier { .optInProof }
    public var maxProjects: Int
    public init(maxProjects: Int = 3) { self.maxProjects = maxProjects }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let roots = [
            "\(home)/Workspace",
            "\(home)/Workspace/10_進行中",
            "\(home)/Developer",
        ]
        var out: [DetectedEntity] = []
        var seen = Set<String>()
        for root in roots {
            guard FileManager.default.fileExists(atPath: root) else { continue }
            for project in Self.findNodeProjects(root: root, limit: maxProjects) {
                let nm = "\(project)/node_modules"
                guard !seen.contains(nm), FileManager.default.fileExists(atPath: nm) else { continue }
                seen.insert(nm)
                let manifest = "\(project)/package.json"
                let lock = Self.findLockfile(project)
                let localOnly = Self.hasLocalOnlyDependencySignal(manifestPath: manifest)
                var rels: [EntityRelationship] = [
                    EntityRelationship(type: .generatedBy, target: "npm/node", presence: .present, confidence: .inferred),
                    EntityRelationship(
                        type: .derivedFrom,
                        target: project,
                        presence: .present,
                        confidence: FileManager.default.fileExists(atPath: manifest) ? .verified : .inferred
                    ),
                    EntityRelationship(
                        type: .belongsToWorkspace,
                        target: project,
                        presence: .present,
                        confidence: .verified
                    ),
                ]
                var reasons: [String] = []
                var conf: EvidenceConfidence = .inferred
                if FileManager.default.fileExists(atPath: manifest), let lock {
                    conf = localOnly ? .inferred : .verified
                    if localOnly { reasons.append(UnknownReasonCode.unknownCustomAsset.rawValue) }
                    rels.append(EntityRelationship(type: .referencedBy, target: lock, presence: .present, confidence: .verified))
                } else {
                    reasons.append(UnknownReasonCode.unknownManifest.rawValue)
                }
                let note = DetectionAnnotation(
                    detectorID: "node.modules.proof",
                    specificity: 115,
                    semanticType: "NODE_MODULES",
                    lifecycle: LifecycleEvidence(role: .generatedArtifact, roleConfidence: .inferred),
                    provenance: ProvenanceEvidence(
                        generatedByProduct: ProductIdentity(name: "Node", confidence: .inferred),
                        relatedWorkspace: project,
                        relatedManifest: manifest,
                        relatedSource: project,
                        creationMechanism: "npm/pnpm/yarn install",
                        storageRole: .generatedArtifact,
                        confidence: conf,
                        unknownReasons: reasons
                    ),
                    relationships: rels,
                    unknownReasons: reasons
                )
                if let n = lightweightNode(
                    id: "node.modules.\(URL(fileURLWithPath: project).lastPathComponent)",
                    kind: .generatedBuild,
                    category: "DEVELOPER",
                    sub: "node_modules",
                    path: nm,
                    scanner: scanner,
                    bucket: bucket,
                    domain: domain,
                    annotation: note
                ) { out.append(n) }
                if out.count >= maxProjects { return out }
            }
        }
        return out
    }

    static func findNodeProjects(root: String, limit: Int) -> [String] {
        var found: [String] = []
        let fm = FileManager.default
        var queue: [(String, Int)] = [(root, 0)]
        while !queue.isEmpty, found.count < limit {
            let (dir, depth) = queue.removeFirst()
            if depth > 4 { continue }
            let nm = "\(dir)/node_modules"
            let pkg = "\(dir)/package.json"
            if fm.fileExists(atPath: nm), fm.fileExists(atPath: pkg) {
                found.append(dir)
                continue
            }
            guard depth < 4 else { continue }
            let kids = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for name in kids.prefix(40) {
                if name == "node_modules" || name == ".git" || name == "dist" || name == "build" { continue }
                let child = "\(dir)/\(name)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue {
                    queue.append((child, depth + 1))
                }
            }
        }
        return found
    }

    static func findLockfile(_ project: String) -> String? {
        for name in ["package-lock.json", "pnpm-lock.yaml", "yarn.lock"] {
            let p = "\(project)/\(name)"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    /// Conservative: any file:/link:/portal: dependency → cannot VERIFIED regenerable.
    static func hasLocalOnlyDependencySignal(manifestPath: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return true }
        let keys = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]
        for key in keys {
            guard let deps = obj[key] as? [String: Any] else { continue }
            for (_, value) in deps {
                let s = "\(value)".lowercased()
                if s.hasPrefix("file:") || s.hasPrefix("link:") || s.hasPrefix("portal:") || s.contains("/../") {
                    return true
                }
            }
        }
        return false
    }
}

public struct ChromeAppSupportDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public var tier: DetectorTier { .should }
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Application Support/Google/Chrome"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let chrome = ProductIdentity(name: "Chrome", bundleIdentifier: "com.google.Chrome", confidence: .inferred)

        let profiles = ChildFolderEnumerator(maxChildren: 8).immediateDirectories(at: root)
            .filter { $0.name == "Default" || $0.name.hasPrefix("Profile") || $0.name == "Guest Profile" || $0.name == "System Profile" }

        let semanticChildren: [(String, LifecycleRole, EntityKind)] = [
            // Code/GPU/Shader Cache intentionally omitted from sized children (runtime).
            // Detected as protected/unknown semantics only for non-huge state folders.
            ("Service Worker", .cache, .cache),
            ("IndexedDB", .database, .applicationSupport),
            ("Local Storage", .database, .applicationSupport),
            ("Session Storage", .session, .applicationSupport),
            ("Extensions", .extensionData, .applicationSupport),
            ("Cookies", .applicationState, .applicationSupport),
            ("History", .history, .applicationSupport),
            ("Preferences", .userConfiguration, .applicationSupport),
            ("WebStorage", .database, .applicationSupport),
        ]

        for profile in profiles {
            // Do NOT measure whole profile root (includes Cache). Children only.
            for child in semanticChildren {
                let path = "\(profile.path)/\(child.0)"
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let roleConf: EvidenceConfidence = .inferred
                var reasons: [String] = []
                if child.1 == .database || child.1 == .history || child.1 == .applicationState {
                    reasons.append(UnknownReasonCode.unknownDatabaseRole.rawValue)
                }
                let note = DetectionAnnotation(
                    detectorID: "chrome.appsupport",
                    specificity: 110,
                    semanticType: "CHROME_\(child.1.rawValue)",
                    lifecycle: LifecycleEvidence(role: child.1, roleConfidence: roleConf),
                    provenance: ProvenanceEvidence(
                        generatedByProduct: chrome,
                        storageRole: child.1,
                        confidence: .inferred,
                        unknownReasons: reasons
                    ),
                    owningProducts: [chrome],
                    unknownReasons: reasons
                )
                if let n = lightweightNode(
                    id: "chrome.profile.\(Self.slug(profile.name)).\(Self.slug(child.0))",
                    kind: child.2,
                    category: "APP_SUPPORT",
                    sub: "Chrome",
                    path: path,
                    scanner: scanner,
                    bucket: bucket,
                    domain: domain,
                    processes: ["Google Chrome", "Chrome"],
                    annotation: note
                ) { out.append(n) }
            }
        }
        return out
    }

    static func slug(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}

public struct TomyLocalInspectorDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public var tier: DetectorTier { .should }
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Application Support/TomyLocal"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let product = ProductIdentity(name: "TomyLocal", confidence: .unknown)
        if let n = lightweightNode(
            id: "tomylocal.root",
            kind: .unknown,
            category: "APP_SUPPORT",
            sub: "TomyLocal",
            path: root,
            scanner: scanner,
            bucket: bucket,
            domain: domain,
            annotation: DetectionAnnotation(
                detectorID: "tomylocal.inspect",
                specificity: 90,
                semanticType: "LOCAL_TOOL_ROOT",
                lifecycle: LifecycleEvidence(role: .mixed, roleConfidence: .unknown, mixedContent: true),
                provenance: ProvenanceEvidence(
                    generatedByProduct: product,
                    storageRole: .mixed,
                    confidence: .unknown,
                    unknownReasons: [UnknownReasonCode.unknownCustomAsset.rawValue]
                ),
                unknownReasons: [UnknownReasonCode.unknownCustomAsset.rawValue, UnknownReasonCode.unknownSourceOfTruth.rawValue]
            )
        ) { out.append(n) }

        for child in ChildFolderEnumerator(maxChildren: 16).immediateDirectories(at: root) {
            let classified = LifecycleArtifactClassifier.classify(name: child.name)
            let role = classified.0 == .unknown ? LifecycleRole.mixed : classified.0
            let note = DetectionAnnotation(
                detectorID: "tomylocal.inspect",
                specificity: 95,
                semanticType: "LOCAL_TOOL_CHILD",
                lifecycle: LifecycleEvidence(role: role, roleConfidence: .unknown, mixedContent: true),
                provenance: ProvenanceEvidence(
                    generatedByProduct: ProductIdentity(name: child.name, confidence: .unknown),
                    storageRole: role,
                    confidence: .unknown,
                    unknownReasons: [UnknownReasonCode.unknownCustomAsset.rawValue]
                ),
                unknownReasons: [UnknownReasonCode.unknownCustomAsset.rawValue]
            )
            if let n = lightweightNode(
                id: "tomylocal.child.\(child.name)",
                kind: .unknown,
                category: "APP_SUPPORT",
                sub: "TomyLocal",
                path: child.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                annotation: note
            ) { out.append(n) }
        }
        return out
    }
}

/// P1.7: workspaceStorage UUID ↔ folder URI from workspace.json (explicit VERIFIED when target exists).
public struct CursorWorkspaceStorageDetector: EntityDetector {
    public let domain = "AI Tools"
    public let bucket = SystemDataBucket.developer
    public var tier: DetectorTier { .should }
    public var maxChildren: Int
    public init(maxChildren: Int = 12) { self.maxChildren = maxChildren }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Application Support/Cursor/User/workspaceStorage"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let cursor = ProductIdentity(name: "Cursor", confidence: .inferred)
        for kid in ChildFolderEnumerator(maxChildren: maxChildren).immediateDirectories(at: root) {
            if kid.name == "empty-window" { continue }
            let jsonPath = "\(kid.path)/workspace.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }
            let folderURI = (obj["folder"] as? String) ?? ""
            let path = CursorWorkspaceIdentityResolver.decodeFileURI(folderURI)
            var reasons: [String] = []
            var conf: EvidenceConfidence = .unknown
            var rels: [EntityRelationship] = []
            if path.isEmpty {
                reasons.append(UnknownReasonCode.cursorWorkspaceURIMissing.rawValue)
            } else if !path.hasPrefix("/") {
                // remote / non-local URI — do not treat as local canonical
                reasons.append(UnknownReasonCode.cursorWorkspacePathMissing.rawValue)
                conf = .unknown
            } else {
                let exists = FileManager.default.fileExists(atPath: path)
                conf = exists ? .verified : .unknown
                rels.append(EntityRelationship(
                    type: .belongsToWorkspace,
                    target: path,
                    presence: exists ? .present : .missing,
                    confidence: conf
                ))
                if !exists { reasons.append(UnknownReasonCode.cursorWorkspaceTargetNotFound.rawValue) }
            }
            let note = DetectionAnnotation(
                detectorID: "cursor.workspaceStorage",
                specificity: 100,
                semanticType: "CURSOR_WORKSPACE_STORAGE",
                lifecycle: LifecycleEvidence(role: .workspaceState, roleConfidence: .inferred),
                provenance: ProvenanceEvidence(
                    generatedByProduct: cursor,
                    relatedWorkspace: path.isEmpty ? nil : path,
                    relatedManifest: jsonPath,
                    storageRole: .workspaceState,
                    confidence: conf,
                    unknownReasons: reasons
                ),
                relationships: rels,
                unknownReasons: reasons
            )
            if let n = lightweightNode(
                id: "cursor.workspaceStorage.\(kid.name)",
                kind: .applicationSupport,
                category: "AI_DEV",
                sub: "Cursor",
                path: kid.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                processes: ["Cursor"],
                annotation: note
            ) { out.append(n) }
        }
        return out
    }
}
