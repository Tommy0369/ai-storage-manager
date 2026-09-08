import Foundation

public struct CursorSnapshotDetector: EntityDetector {
    public let domain = "AI Tools"
    public let bucket = SystemDataBucket.developer
    public var maxInstances: Int
    public init(maxInstances: Int = 16) {
        self.maxInstances = maxInstances
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Application Support/Cursor/snapshots"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let cursor = ProductIdentity(name: "Cursor", bundleIdentifier: nil, confidence: .inferred)
        func note(_ semantic: String, role: LifecycleRole, conf: EvidenceConfidence, rels: [EntityRelationship] = [], reasons: [String] = [], spec: Int = 100) -> DetectionAnnotation {
            DetectionAnnotation(
                detectorID: "cursor.snapshot",
                specificity: spec,
                semanticType: semantic,
                lifecycle: LifecycleEvidence(role: role, roleConfidence: conf, activeState: .unknown, unknownReasons: [UnknownReasonCode.activeStateUnknown.rawValue]),
                provenance: ProvenanceEvidence(
                    generatedByProduct: cursor,
                    relatedWorkspace: rels.first { $0.type == .belongsToWorkspace }?.target,
                    storageRole: role,
                    confidence: conf,
                    unknownReasons: reasons
                ),
                relationships: rels,
                unknownReasons: reasons
            )
        }
        if let n = node(
            id: "cursor.snapshots.root",
            kind: .generatedBuild,
            category: "AI_DEV",
            sub: "Cursor",
            path: root,
            scanner: scanner,
            bucket: bucket,
            domain: domain,
            processes: ["Cursor"],
            annotation: note("CURSOR_SNAPSHOT_ROOT", role: .snapshot, conf: .inferred, reasons: [UnknownReasonCode.lifecycleMixedContent.rawValue])
        ) { out.append(n) }

        let layers: [(String, String, LifecycleRole, String)] = [
            ("cursor.snapshots.codebases", "\(root)/codebases", .snapshot, "CURSOR_SNAPSHOT_INSTANCE"),
            ("cursor.snapshots.roots", "\(root)/roots", .workspaceState, "CURSOR_SNAPSHOT_METADATA"),
            ("cursor.snapshots.state", "\(root)/state", .applicationState, "CURSOR_SNAPSHOT_STATE"),
            ("cursor.snapshots.stores", "\(root)/stores", .generatedArtifact, "CURSOR_SNAPSHOT_GENERATED"),
        ]
        for layer in layers {
            if let n = node(id: layer.0, kind: .generatedBuild, category: "AI_DEV", sub: "Cursor", path: layer.1, scanner: scanner, bucket: bucket, domain: domain, processes: ["Cursor"], annotation: note(layer.3, role: layer.2, conf: .inferred)) {
                out.append(n)
            }
        }

        if let n = node(
            id: "cursor.snapshots.database",
            kind: .applicationSupport,
            category: "AI_DEV",
            sub: "Cursor",
            path: "\(root)/state/state.db",
            scanner: scanner,
            bucket: bucket,
            domain: domain,
            processes: ["Cursor"],
            annotation: note("CURSOR_SNAPSHOT_DATABASE", role: .database, conf: .inferred, reasons: [UnknownReasonCode.lifecycleDatabaseUnknown.rawValue])
        ) { out.append(n) }

        let instances = ChildFolderEnumerator(maxChildren: maxInstances).immediateDirectories(at: "\(root)/codebases")
        for inst in instances {
            if let n = node(
                id: "cursor.snapshots.instance.\(inst.name)",
                kind: .generatedBuild,
                category: "AI_DEV",
                sub: "Cursor",
                path: inst.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                processes: ["Cursor"],
                annotation: note("CURSOR_SNAPSHOT_INSTANCE", role: .snapshot, conf: .inferred, reasons: [UnknownReasonCode.provenanceNoManifest.rawValue])
            ) { out.append(n) }
            for child in ["objects", "refs", "staging"] {
                let role: LifecycleRole = child == "staging" ? .temporary : (child == "objects" ? .generatedArtifact : .index)
                if let n = node(
                    id: "cursor.snapshots.instance.\(inst.name).\(child)",
                    kind: child == "staging" ? .temp : .generatedBuild,
                    category: "AI_DEV",
                    sub: "Cursor",
                    path: "\(inst.path)/\(child)",
                    scanner: scanner,
                    bucket: bucket,
                    domain: domain,
                    processes: ["Cursor"],
                    annotation: note(child == "objects" ? "CURSOR_SNAPSHOT_GENERATED" : "CURSOR_SNAPSHOT_STATE", role: role, conf: .inferred)
                ) { out.append(n) }
            }
        }

        let identityIndex = CursorWorkspaceIdentityResolver.sharedIndex(home: home)
        let roots = ChildFolderEnumerator(maxChildren: 24).immediateDirectories(at: "\(root)/roots")
        for r in roots {
            let identity = CursorWorkspaceIdentityResolver.resolveRoot(rootFolderName: r.name, home: home, index: identityIndex)
            let rels = identity.workspaceRelationships()
            var reasons: [String] = []
            if let ws = rels.first(where: { $0.type == .belongsToWorkspace }), ws.presence == .missing {
                reasons.append(UnknownReasonCode.workspaceReferenceMissing.rawValue)
            }
            if let reason = identity.unknownReason { reasons.append(reason) }
            if identity.relationshipConfidence == .unknown {
                reasons.append(UnknownReasonCode.unknownWorkspaceRelation.rawValue)
            }
            let marker = "\(r.path)/baseline.marker"
            _ = marker
            if let n = node(
                id: "cursor.snapshots.rootref.\(r.name)",
                kind: .generatedBuild,
                category: "AI_DEV",
                sub: "Cursor",
                path: r.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                processes: ["Cursor"],
                annotation: note(
                    "CURSOR_SNAPSHOT_METADATA",
                    role: .workspaceState,
                    conf: identity.relationshipConfidence,
                    rels: rels,
                    reasons: reasons
                )
            ) { out.append(n) }
        }
        return out
    }
}

public struct ClaudeVMBundleDetector: EntityDetector {
    public let domain = "AI Tools"
    public let bucket = SystemDataBucket.developer
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Application Support/Claude/vm_bundles"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        let product = ProductIdentity(name: "Claude Desktop", confidence: .inferred)
        let appVersion = VersionRelationshipResolver.claudeDesktopVersion()
        func note(_ semantic: String, role: LifecycleRole, reasons: [String] = [], rels: [EntityRelationship] = []) -> DetectionAnnotation {
            DetectionAnnotation(
                detectorID: "claude.vm",
                specificity: 100,
                semanticType: semantic,
                lifecycle: LifecycleEvidence(role: role, roleConfidence: .inferred, activeState: .unknown, unknownReasons: [UnknownReasonCode.activeStateUnknown.rawValue]),
                provenance: ProvenanceEvidence(generatedByProduct: product, generatedByVersion: appVersion, storageRole: role, confidence: .inferred, unknownReasons: reasons),
                relationships: rels,
                unknownReasons: reasons
            )
        }
        if let n = node(id: "claude.vm.root", kind: .applicationSupport, category: "AI_DEV", sub: "Claude", path: root, scanner: scanner, bucket: bucket, domain: domain, processes: ["Claude"], annotation: note("CLAUDE_VM_BUNDLE", role: .runtime, reasons: [UnknownReasonCode.lifecycleMixedContent.rawValue])) {
            out.append(n)
        }
        if let n = node(id: "claude.vm.warm", kind: .cache, category: "AI_DEV", sub: "Claude", path: "\(root)/warm", scanner: scanner, bucket: bucket, domain: domain, processes: ["Claude"], annotation: note("CLAUDE_VM_CACHE", role: .cache)) {
            out.append(n)
        }
        let bundles = ChildFolderEnumerator(maxChildren: 8).immediateDirectories(at: root)
        for bundle in bundles where bundle.name.hasSuffix(".bundle") || bundle.name.contains("vm") {
            let origin = "\(bundle.path)/.rootfs.img.origin"
            let token = (try? String(contentsOfFile: origin, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            let related = VersionRelationshipResolver.relate(appVersion: appVersion, artifactToken: token)
            var reasons: [String] = []
            if related.0 != .verified { reasons.append(UnknownReasonCode.versionRelationUnknown.rawValue) }
            let versionRel = EntityRelationship(
                type: .belongsToVersion,
                target: appVersion ?? "unknown",
                presence: appVersion == nil ? .unknown : .present,
                confidence: related.0
            )
            if let n = node(id: "claude.vm.bundle.\(bundle.name)", kind: .applicationSupport, category: "AI_DEV", sub: "Claude", path: bundle.path, scanner: scanner, bucket: bucket, domain: domain, processes: ["Claude"], annotation: note("CLAUDE_VM_BUNDLE", role: .runtime, reasons: reasons, rels: [versionRel])) {
                out.append(n)
            }
            let parts: [(String, String, EntityKind, LifecycleRole, String)] = [
                ("\(bundle.name).runtime", "\(bundle.path)/rootfs.img", .generatedBuild, .runtime, "CLAUDE_VM_RUNTIME_IMAGE"),
                ("\(bundle.name).kernel", "\(bundle.path)/vmlinuz", .generatedBuild, .runtime, "CLAUDE_VM_RUNTIME_IMAGE"),
                ("\(bundle.name).writable", "\(bundle.path)/sessiondata.img", .applicationSupport, .applicationState, "CLAUDE_VM_WRITABLE_STATE"),
                ("\(bundle.name).metadata", "\(bundle.path)/machineIdentifier", .applicationSupport, .userConfiguration, "CLAUDE_VM_METADATA"),
            ]
            for p in parts {
                if let n = node(id: "claude.vm.bundle.\(p.0)", kind: p.2, category: "AI_DEV", sub: "Claude", path: p.1, scanner: scanner, bucket: bucket, domain: domain, processes: ["Claude"], annotation: note(p.4, role: p.3, reasons: reasons, rels: [versionRel])) {
                    out.append(n)
                }
            }
        }
        return out
    }
}

public struct IOSBackupDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.backup
    public var maxDevices: Int
    public init(maxDevices: Int = 12) {
        self.maxDevices = maxDevices
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Application Support/MobileSync/Backup"
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var out: [DetectedEntity] = []
        func note(_ semantic: String, device: String?, reasons: [String], rels: [EntityRelationship] = []) -> DetectionAnnotation {
            DetectionAnnotation(
                detectorID: "ios.backup",
                specificity: 100,
                semanticType: semantic,
                lifecycle: LifecycleEvidence(role: .backup, roleConfidence: .inferred, unknownReasons: [UnknownReasonCode.activeStateUnknown.rawValue]),
                provenance: ProvenanceEvidence(relatedDevice: device, storageRole: .backup, confidence: device == nil ? .unknown : .verified, unknownReasons: reasons),
                relationships: rels,
                unknownReasons: reasons
            )
        }
        if let n = node(id: "ios.backup.root", kind: .userOriginal, category: "BACKUP", sub: "IOS", path: root, scanner: scanner, bucket: bucket, domain: domain, annotation: note("IOS_BACKUP_ROOT", device: nil, reasons: [UnknownReasonCode.lifecycleMixedContent.rawValue])) {
            out.append(n)
        }
        let devices = ChildFolderEnumerator(maxChildren: maxDevices).immediateDirectories(at: root)
        for device in devices {
            let meta = Self.readMetadata(device.path)
            var reasons: [String] = []
            if meta.info == nil { reasons.append(UnknownReasonCode.deviceMetadataUnavailable.rawValue) }
            let rels = DeviceRelationshipResolver.backupOf(deviceID: device.name, deviceName: meta.deviceName)
            if let n = node(
                id: "ios.backup.device.\(device.name)",
                kind: .userOriginal,
                category: "BACKUP",
                sub: meta.deviceName ?? device.name,
                path: device.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                annotation: note("IOS_DEVICE_BACKUP", device: device.name, reasons: reasons, rels: rels)
            ) { out.append(n) }
            for (suffix, file, semantic) in [
                ("status", "Status.plist", "IOS_BACKUP_METADATA"),
                ("info", "Info.plist", "IOS_BACKUP_METADATA"),
                ("manifest", "Manifest.plist", "IOS_BACKUP_MANIFEST"),
                ("manifest_db", "Manifest.db", "IOS_BACKUP_DATABASE"),
            ] {
                if let n = node(
                    id: "ios.backup.device.\(device.name).\(suffix)",
                    kind: .applicationSupport,
                    category: "BACKUP",
                    sub: meta.deviceName ?? device.name,
                    path: "\(device.path)/\(file)",
                    scanner: scanner,
                    bucket: bucket,
                    domain: domain,
                    annotation: note(semantic, device: device.name, reasons: reasons, rels: rels)
                ) { out.append(n) }
            }
        }
        return out
    }

    struct BackupMeta {
        var deviceName: String?
        var info: [String: Any]?
    }

    static func readMetadata(_ backupDir: String) -> BackupMeta {
        var meta = BackupMeta()
        for name in ["Info.plist", "Status.plist", "Manifest.plist"] {
            let path = "\(backupDir)/\(name)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            if name == "Info.plist" {
                meta.info = obj
                meta.deviceName = obj["Device Name"] as? String
            }
            if meta.deviceName == nil, let n = obj["DeviceName"] as? String { meta.deviceName = n }
        }
        return meta
    }
}

public struct ContainerLifecycleDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        ContainerDeepDetector().detect(home: home, scanner: scanner)
    }
}

public struct AppSupportLifecycleDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public init() {}
    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        []
    }
}

public struct GroupContainerLifecycleDetector: EntityDetector {
    public let domain = "macOS"
    public let bucket = SystemDataBucket.developer
    public init() {}

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let root = "\(home)/Library/Group Containers"
        let kids = ChildFolderEnumerator(maxChildren: 20).immediateDirectories(at: root)
        var out: [DetectedEntity] = []
        for kid in kids {
            let identity = ProductIdentityResolver.resolve(bundleID: kid.name)
            var reasons: [String] = []
            if identity.confidence == .unknown { reasons.append(UnknownReasonCode.provenanceOwnerUnknown.rawValue) }
            let note = DetectionAnnotation(
                detectorID: "groupcontainer.lifecycle",
                specificity: 70,
                semanticType: "GROUP_CONTAINER",
                lifecycle: LifecycleEvidence(role: .mixed, roleConfidence: .inferred, mixedContent: true, unknownReasons: [UnknownReasonCode.lifecycleMixedContent.rawValue]),
                provenance: ProvenanceEvidence(generatedByProduct: identity, bundleIdentifier: kid.name, storageRole: .mixed, confidence: identity.confidence, unknownReasons: reasons),
                owningProducts: [identity],
                unknownReasons: reasons
            )
            if let n = node(
                id: "groupcontainer.\(kid.name)",
                kind: .applicationSupport,
                category: "CONTAINER",
                sub: identity.name ?? kid.name,
                path: kid.path,
                scanner: scanner,
                bucket: bucket,
                domain: domain,
                annotation: note
            ) { out.append(n) }
        }
        return out
    }
}
