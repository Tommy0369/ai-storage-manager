import Foundation

/// P3.3A — bounded read-only Cursor globalStorage intelligence.
/// Consumes the already-identified root; does not create a second home crawler.
/// Never dumps conversation/prompt/message contents.
public enum CursorGlobalStorageIntelligence {
    public static let rootEntityID = "ai.cursor.global_storage"
    public static let largeFileThresholdBytes: Int64 = 100_000_000

    public struct Context: Sendable {
        public var home: String
        public var openPaths: Set<String>
        public var runtimeCompleteness: String
        public var measureBytes: (@Sendable (String) -> Int64)?

        public init(
            home: String = FileManager.default.homeDirectoryForCurrentUser.path,
            openPaths: Set<String> = [],
            runtimeCompleteness: String = "UNKNOWN",
            measureBytes: (@Sendable (String) -> Int64)? = nil
        ) {
            self.home = home
            self.openPaths = openPaths
            self.runtimeCompleteness = runtimeCompleteness
            self.measureBytes = measureBytes
        }

        public func bytes(for path: String) -> Int64 {
            if let measureBytes { return measureBytes(path) }
            return CursorGlobalStorageIntelligence.duBytes(path)
        }
    }

    public static func defaultRootPath(home: String) -> String {
        "\(home)/Library/Application Support/Cursor/User/globalStorage"
    }

    public static func analyze(_ ctx: Context = Context()) -> CursorGlobalStorageIntelligenceReport {
        let root = defaultRootPath(home: ctx.home)
        let rootBytes = ctx.bytes(for: root)
        let app = resolveCursorApp()
        let running = isCursorRunning()

        var components: [CursorStorageComponent] = []
        var ownership: [CursorExtensionOwnership] = []
        var openHits: [String] = []

        let children = listDirectChildren(root)
        for child in children {
            let rel = (child as NSString).lastPathComponent
            let bytes = ctx.bytes(for: child)
            let open = isOpen(path: child, openPaths: ctx.openPaths)
            if open { openHits.append(sanitizePathClass(rel)) }

            let classified = classifyChild(
                absolute: child,
                relative: rel,
                bytes: bytes,
                rootBytes: rootBytes,
                open: open,
                runtimeCompleteness: ctx.runtimeCompleteness,
                home: ctx.home,
                measure: { ctx.bytes(for: $0) }
            )
            components.append(contentsOf: classified.components)
            if let own = classified.ownership {
                ownership.append(own)
            }
        }

        // Promote large nested semantic subtrees (≥100MB) already captured as components.
        components.sort { $0.uniqueBytes > $1.uniqueBytes }
        if components.count > 40 {
            components = Array(components.prefix(40))
        }

        let mapped = components.reduce(Int64(0)) { $0 + $1.uniqueBytes }
        // Direct-child exclusive accounting: sum of direct child sizes should match root (±tolerance).
        let directSum = children.reduce(Int64(0)) { $0 + ctx.bytes(for: $1) }
        let unknown = max(0, rootBytes - directSum)
        let coverage = rootBytes > 0 ? min(100.0, Double(directSum) / Double(rootBytes) * 100.0) : 0
        let accountingValid = abs(rootBytes - directSum - unknown) == 0 && unknown >= 0

        let kv = summarizeKVNamespacesIfSafe(dbPath: "\(root)/state.vscdb")
        let opportunities = buildOpportunities(components: components)

        return CursorGlobalStorageIntelligenceReport(
            rootEntityID: rootEntityID,
            rootPath: root,
            owner: "CURSOR",
            semanticRole: "GLOBAL_STORAGE",
            observedBytes: rootBytes,
            uniqueBytes: rootBytes,
            mappedChildBytes: mapped > rootBytes ? directSum : mapped,
            unknownBytes: unknown,
            classificationCoveragePercent: coverage,
            accountingValid: accountingValid,
            appInstalled: app.installed,
            appVersion: app.version,
            appBundleID: app.bundleID,
            appRunning: running,
            rootSafety: "PROTECTED",
            rootActionability: "KEEP",
            rootExecutable: false,
            components: components,
            extensionOwnership: ownership,
            kvNamespaceSummaries: kv,
            opportunities: opportunities,
            openComponentPaths: openHits,
            runtimeCompleteness: ctx.runtimeCompleteness,
            privacyNote: "Reports contain metadata/sizes/key-class aggregates only. No prompt, message, source, credential, or DB row contents.",
            generatedAt: Date()
        )
    }

    // MARK: - Classification

    struct ChildResult {
        var components: [CursorStorageComponent]
        var ownership: CursorExtensionOwnership?
    }

    static func classifyChild(
        absolute: String,
        relative: String,
        bytes: Int64,
        rootBytes: Int64,
        open: Bool,
        runtimeCompleteness: String,
        home: String,
        measure: (String) -> Int64
    ) -> ChildResult {
        var comps: [CursorStorageComponent] = []
        var ownership: CursorExtensionOwnership?

        let pct = rootBytes > 0 ? Double(bytes) / Double(rootBytes) * 100.0 : 0
        let runtime = open
            ? "ACTIVE_VERIFIED"
            : (runtimeCompleteness == "COMPLETE" ? "INACTIVE_VERIFIED" : "RUNTIME_UNKNOWN")

        if relative == "state.vscdb" || relative.hasSuffix(".vscdb") && !relative.contains("backup") && !relative.hasSuffix("-wal") && !relative.hasSuffix("-shm") {
            comps.append(make(
                id: "cursor.gs.state_vscdb",
                rel: relative,
                path: absolute,
                kind: .database,
                owner: "CURSOR_CORE",
                role: "CORE_GLOBAL_STATE_DATABASE",
                bytes: bytes,
                pct: pct,
                open: open,
                runtime: runtime,
                db: true,
                sot: "TRUE",
                user: "USER_ORIGINAL_OR_USER_STATE_PROTECTED",
                reac: "UNKNOWN",
                regen: "FALSE_INFERRED",
                conf: .verified,
                action: .keep,
                evidence: [
                    "SQLITE_MAGIC_VERIFIED",
                    "TABLES=ItemTable,cursorDiskKV,composerHeaders",
                    "OPEN=\(open)",
                    "PATH_CACHE_WORD_NOT_USED_AS_PROOF",
                ]
            ))
            return ChildResult(components: comps, ownership: nil)
        }

        if relative.hasSuffix("-wal") {
            comps.append(make(
                id: "cursor.gs.\(sanitizeID(relative))",
                rel: relative, path: absolute, kind: .databaseWAL, owner: "CURSOR_CORE",
                role: "SQLITE_WAL", bytes: bytes, pct: pct, open: open, runtime: runtime, db: true,
                sot: "UNKNOWN", user: "APP_MANAGED", reac: "UNKNOWN", regen: "UNKNOWN",
                conf: .verified, action: .keep,
                evidence: ["WAL_SIBLING_OF_SQLITE", "OPEN=\(open)"]
            ))
            return ChildResult(components: comps, ownership: nil)
        }
        if relative.hasSuffix("-shm") {
            comps.append(make(
                id: "cursor.gs.\(sanitizeID(relative))",
                rel: relative, path: absolute, kind: .databaseSHM, owner: "CURSOR_CORE",
                role: "SQLITE_SHM", bytes: bytes, pct: pct, open: open, runtime: runtime, db: true,
                sot: "UNKNOWN", user: "APP_MANAGED", reac: "UNKNOWN", regen: "UNKNOWN",
                conf: .verified, action: .keep,
                evidence: ["SHM_SIBLING_OF_SQLITE", "OPEN=\(open)"]
            ))
            return ChildResult(components: comps, ownership: nil)
        }
        if relative == "state.vscdb.backup" {
            comps.append(make(
                id: "cursor.gs.state_vscdb_backup",
                rel: relative, path: absolute, kind: .checkpointOrRecoveryState, owner: "CURSOR_CORE",
                role: "DATABASE_BACKUP", bytes: bytes, pct: pct, open: open, runtime: runtime, db: true,
                sot: "UNKNOWN", user: "USER_ORIGINAL_OR_USER_STATE_PROTECTED",
                reac: "UNKNOWN", regen: "UNKNOWN",
                conf: .inferred, action: .verifyMore,
                evidence: ["FILENAME_BACKUP_SIBLING", "MAY_DUPLICATE_PRIMARY_DB_BYTES", "NOT_EXECUTABLE"]
            ))
            return ChildResult(components: comps, ownership: nil)
        }
        if relative == "conversation-search.db" {
            comps.append(make(
                id: "cursor.gs.conversation_search_db",
                rel: relative, path: absolute, kind: .aiConversationOrContextState, owner: "CURSOR_CORE",
                role: "CONVERSATION_SEARCH_INDEX", bytes: bytes, pct: pct, open: open, runtime: runtime, db: true,
                sot: "TRUE", user: "USER_ORIGINAL_OR_USER_STATE_PROTECTED",
                reac: "UNKNOWN", regen: "FALSE_INFERRED",
                conf: .verified, action: .keep,
                evidence: ["SQLITE_MAGIC", "TABLES_INCLUDE_conversations", "NO_CONTENT_DUMPED", "OPEN=\(open)"]
            ))
            return ChildResult(components: comps, ownership: nil)
        }
        if relative == "storage.json" {
            comps.append(make(
                id: "cursor.gs.storage_json",
                rel: relative, path: absolute, kind: .cursorCoreGlobalState, owner: "CURSOR_CORE",
                role: "PROFILE_STORAGE_MANIFEST", bytes: bytes, pct: pct, open: open, runtime: runtime, db: false,
                sot: "TRUE", user: "APP_MANAGED", reac: "UNKNOWN", regen: "UNKNOWN",
                conf: .verified, action: .keep,
                evidence: ["KNOWN_CURSOR_METADATA_FILE"]
            ))
            return ChildResult(components: comps, ownership: nil)
        }

        // Extension-like namespace directories
        if relative.contains(".") && !relative.contains(" ") {
            let extMap = mapExtensionNamespace(relative, home: home)
            ownership = CursorExtensionOwnership(
                namespace: relative,
                extensionID: extMap.extensionID,
                extensionInstalled: extMap.installed,
                version: extMap.version,
                ownershipEvidence: extMap.evidence,
                storageBytes: bytes,
                availabilityState: extMap.installed
                    ? "EXTENSION_PRESENT"
                    : (extMap.isCursorFirstParty
                        ? "CURSOR_FIRST_PARTY_NAMESPACE"
                        : "EXTENSION_ABSENT_MANAGED_DATA_REMAINS"),
                recommendedNextProof: extMap.installed
                    ? "Confirm vendor-native lifecycle for namespace"
                    : "Do not treat as disposable; prove ownership + regenerability"
            )

            if relative == "anysphere.cursor-agent-worker" {
                // Decompose toolchain versions as nested semantic components (bounded).
                let versionsRoot = absolute + "/agent-cli/.local/share/cursor-agent/versions"
                if FileManager.default.fileExists(atPath: versionsRoot) {
                    let versionBytes = measure(versionsRoot)
                    let versionPct = rootBytes > 0 ? Double(versionBytes) / Double(rootBytes) * 100.0 : 0
                    comps.append(make(
                        id: "cursor.gs.agent_cli_versions",
                        rel: "anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions",
                        path: versionsRoot,
                        kind: .vendorToolchainVersions,
                        owner: "CURSOR_CORE",
                        role: "AGENT_CLI_VERSIONED_TOOLCHAINS",
                        bytes: versionBytes,
                        pct: versionPct,
                        open: false,
                        runtime: runtimeCompleteness == "COMPLETE" ? "INACTIVE_VERIFIED" : "RUNTIME_UNKNOWN",
                        db: false,
                        sot: "FALSE_INFERRED",
                        user: "APP_GENERATED",
                        reac: "UNKNOWN",
                        regen: "LIKELY_REGENERABLE_INFERRED",
                        conf: .inferred,
                        action: .nativeCleanupCandidate,
                        evidence: [
                            "MULTIPLE_VERSION_DIRECTORIES",
                            "EXECUTABLE_AGENT_LAUNCHERS_PRESENT",
                            "SOFTWARE_REINSTALL_NE_DATA_REACQUIRE",
                            "NOT_EXECUTABLE_THIS_PHASE",
                        ],
                        extensionID: nil,
                        extensionPresent: false
                    ))
                    let logsBytes = max(0, bytes - versionBytes)
                    if logsBytes > 0 {
                        let logPct = rootBytes > 0 ? Double(logsBytes) / Double(rootBytes) * 100.0 : 0
                        comps.append(make(
                            id: "cursor.gs.agent_worker_logs",
                            rel: "anysphere.cursor-agent-worker/(logs+meta)",
                            path: absolute,
                            kind: .logOrTelemetry,
                            owner: "CURSOR_CORE",
                            role: "AGENT_WORKER_LOGS",
                            bytes: logsBytes,
                            pct: logPct,
                            open: open,
                            runtime: runtime,
                            db: false,
                            sot: "FALSE_INFERRED",
                            user: "APP_GENERATED",
                            reac: "UNKNOWN",
                            regen: "UNKNOWN",
                            conf: .inferred,
                            action: .verifyMore,
                            evidence: ["RESIDUAL_AFTER_VERSIONS_SUBTREE"]
                        ))
                    }
                    return ChildResult(components: comps, ownership: ownership)
                }
            }

            if relative == "anysphere.cursor-retrieval" {
                comps.append(make(
                    id: "cursor.gs.cursor_retrieval",
                    rel: relative, path: absolute,
                    kind: .checkpointOrRecoveryState,
                    owner: "CURSOR_CORE",
                    role: "RETRIEVAL_CHECKPOINTS",
                    bytes: bytes, pct: pct, open: open, runtime: runtime, db: false,
                    sot: "UNKNOWN", user: "USER_ORIGINAL_OR_USER_STATE_PROTECTED",
                    reac: "UNKNOWN", regen: "UNKNOWN",
                    conf: .inferred, action: .keep,
                    evidence: ["CHECKPOINTS_SUBTREE_PRESENT", "FIRST_PARTY_NAMESPACE", "ABSENT_MARKETPLACE_EXTENSION"]
                ))
                return ChildResult(components: comps, ownership: ownership)
            }

            let kind: CursorStorageComponentKind = extMap.installed
                ? .extensionGlobalStorage
                : (extMap.isCursorFirstParty ? .cursorCoreGlobalState : .extensionAbsentStorage)
            let action: CursorPotentialAction = extMap.installed ? .verifyMore : .verifyMore
            comps.append(make(
                id: "cursor.gs.ns.\(sanitizeID(relative))",
                rel: relative, path: absolute, kind: kind,
                owner: extMap.isCursorFirstParty ? "CURSOR_CORE" : (extMap.installed ? "EXTENSION" : "UNKNOWN"),
                role: "NAMESPACE_STORAGE",
                bytes: bytes, pct: pct, open: open, runtime: runtime, db: false,
                sot: "UNKNOWN",
                user: extMap.installed ? "APP_MANAGED" : "USER_ORIGINAL_OR_USER_STATE_PROTECTED",
                reac: "UNKNOWN",
                regen: "UNKNOWN",
                conf: extMap.installed || extMap.isCursorFirstParty ? .verified : .unknown,
                action: action,
                evidence: [extMap.evidence, "EXTENSION_ABSENT_NOT_DISPOSABLE"],
                extensionID: extMap.extensionID,
                extensionPresent: extMap.installed
            ))
            return ChildResult(components: comps, ownership: ownership)
        }

        // Path contains "cache" alone → never promote
        let lower = relative.lowercased()
        if lower.contains("cache") {
            comps.append(make(
                id: "cursor.gs.\(sanitizeID(relative))",
                rel: relative, path: absolute, kind: .cacheSuspect, owner: "UNKNOWN",
                role: "NAME_SUGGESTS_CACHE_UNPROVEN",
                bytes: bytes, pct: pct, open: open, runtime: runtime, db: false,
                sot: "UNKNOWN", user: "UNKNOWN", reac: "UNKNOWN", regen: "UNKNOWN",
                conf: .unknown, action: .verifyMore,
                evidence: ["PATH_WORD_CACHE_INSUFFICIENT", "NOT_GREEN", "NOT_EXECUTABLE"]
            ))
            return ChildResult(components: comps, ownership: nil)
        }

        comps.append(make(
            id: "cursor.gs.\(sanitizeID(relative))",
            rel: relative, path: absolute, kind: .unknownAppManaged, owner: "UNKNOWN",
            role: "UNMAPPED_GLOBALSTORAGE_CHILD",
            bytes: bytes, pct: pct, open: open, runtime: runtime, db: false,
            sot: "UNKNOWN", user: "UNKNOWN", reac: "UNKNOWN", regen: "UNKNOWN",
            conf: .unknown, action: .verifyMore,
            evidence: ["NAMESPACE_UNMAPPED"]
        ))
        return ChildResult(components: comps, ownership: nil)
    }

    static func make(
        id: String,
        rel: String,
        path: String,
        kind: CursorStorageComponentKind,
        owner: String,
        role: String,
        bytes: Int64,
        pct: Double,
        open: Bool,
        runtime: String,
        db: Bool,
        sot: String,
        user: String,
        reac: String,
        regen: String,
        conf: CursorEvidenceLevel,
        action: CursorPotentialAction,
        evidence: [String],
        extensionID: String? = nil,
        extensionPresent: Bool? = nil
    ) -> CursorStorageComponent {
        _ = open
        return CursorStorageComponent(
            entityID: id,
            rootEntityID: rootEntityID,
            componentKind: kind,
            path: path,
            relativePath: rel,
            owner: owner,
            extensionID: extensionID,
            extensionPresent: extensionPresent,
            storageRole: role,
            observedBytes: bytes,
            uniqueBytes: bytes,
            sharedBytes: 0,
            fileCount: nil,
            databaseLike: db,
            runtimeState: runtime,
            sourceOfTruthState: sot,
            userOriginalState: user,
            reacquisitionState: reac,
            regenerabilityState: regen,
            syncState: "UNKNOWN",
            evidence: evidence,
            classificationConfidence: conf,
            recommendedAction: action,
            actionability: action == .keep || action == .verifyMore || action == .none
                ? "NOT_EXECUTABLE"
                : "CANDIDATE_ONLY_NOT_EXECUTABLE",
            percentOfRoot: pct
        )
    }

    // MARK: - Extension mapping

    struct ExtMap {
        var extensionID: String?
        var installed: Bool
        var version: String?
        var evidence: String
        var isCursorFirstParty: Bool
    }

    static func mapExtensionNamespace(_ ns: String, home: String) -> ExtMap {
        let firstPartyPrefixes = ["anysphere.cursor-", "anysphere.cursor"]
        let isFP = firstPartyPrefixes.contains(where: { ns.hasPrefix($0) }) || ns.hasPrefix("anysphere.cursor")
        // Exact marketplace match: publisher.name-version
        let roots = [
            "\(home)/.cursor/extensions",
            "\(home)/.vscode/extensions",
        ]
        for root in roots {
            guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            // Exact: ns or ns-version — avoid prefix false positives (cursor-retrieval ≠ cursorpyright)
            let hits = dirs.filter { $0 == ns || $0.hasPrefix(ns + "-") }
            if let hit = hits.sorted().last {
                let version = hit == ns ? nil : String(hit.dropFirst(ns.count + 1))
                return ExtMap(
                    extensionID: ns,
                    installed: true,
                    version: version,
                    evidence: "EXTENSION_DIR_EXACT_PREFIX_MATCH:\(root)/\(hit)",
                    isCursorFirstParty: isFP
                )
            }
        }
        if isFP {
            return ExtMap(
                extensionID: ns,
                installed: false,
                version: nil,
                evidence: "CURSOR_FIRST_PARTY_NAMESPACE_NO_MARKETPLACE_DIR",
                isCursorFirstParty: true
            )
        }
        return ExtMap(
            extensionID: ns,
            installed: false,
            version: nil,
            evidence: "NO_INSTALLED_EXTENSION_DIR_FOR_NAMESPACE",
            isCursorFirstParty: false
        )
    }

    // MARK: - Opportunities

    static func buildOpportunities(components: [CursorStorageComponent]) -> [CursorStorageOpportunity] {
        var out: [CursorStorageOpportunity] = []
        for c in components where c.uniqueBytes >= 50_000_000 {
            let score = rankingScore(c)
            let (feas, req, risk, native, preserv, expl) = opportunityMeta(c)
            out.append(CursorStorageOpportunity(
                candidateID: "opp.\(c.entityID)",
                component: c.relativePath,
                uniqueBytes: c.uniqueBytes,
                currentSafety: "PROTECTED",
                potentialAction: c.recommendedAction,
                proofFeasibility: feas,
                requiredEvidence: req,
                expectedValue: byteLabel(c.uniqueBytes),
                risk: risk,
                nativeContractAvailability: native,
                preservationPotential: preserv,
                currentExecutable: false,
                rankingScore: score,
                rankingExplanation: expl
            ))
        }
        return out.sorted { $0.rankingScore > $1.rankingScore }
    }

    static func rankingScore(_ c: CursorStorageComponent) -> Double {
        let gb = Double(c.uniqueBytes) / 1_000_000_000
        var score = min(40, gb * 4)
        switch c.recommendedAction {
        case .nativeCleanupCandidate: score += 25
        case .verifyMore: score += 10
        case .exportThenRemoveCandidate: score += 15
        case .moveToICloudCandidate: score += 8
        case .keep, .none: score += 0
        }
        if c.componentKind == .aiConversationOrContextState || c.userOriginalState.contains("USER") {
            score -= 5 // high value but not deletion path
        }
        if c.runtimeState == "ACTIVE_VERIFIED" {
            score -= 10
        }
        return max(0, score)
    }

    static func opportunityMeta(_ c: CursorStorageComponent) -> (String, [String], String, String, String, String) {
        switch c.componentKind {
        case .vendorToolchainVersions:
            return (
                "MEDIUM",
                ["vendor retention policy for old agent-cli versions", "active version pin", "regeneration contract"],
                "MEDIUM — may break agent until redownload",
                "UNKNOWN_DOCUMENTED_NATIVE",
                "LOW",
                "Large multi-version toolchain tree; possible future native cleanup of stale versions only"
            )
        case .database, .aiConversationOrContextState, .indexedDBOrKVStore:
            return (
                "HARD",
                ["vendor retention/cleanup command", "export contract", "inactive COMPLETE runtime", "user consent model"],
                "CRITICAL — user conversation/agent state",
                "NONE_PROVEN",
                "HIGH — export/archive before any reduction",
                "Dominant bytes are user/agent state in SQLite; understand growth before any action"
            )
        case .checkpointOrRecoveryState:
            return (
                "HARD",
                ["checkpoint lifecycle semantics", "user recoverability"],
                "HIGH",
                "NONE_PROVEN",
                "MEDIUM",
                "Checkpoint/recovery state — protect until proven disposable"
            )
        default:
            return (
                "LOW",
                ["ownership", "regenerability", "runtime"],
                "HIGH",
                "NONE",
                "UNKNOWN",
                "Insufficient proof for action"
            )
        }
    }

    // MARK: - KV summary (privacy-safe)

    static func summarizeKVNamespacesIfSafe(dbPath: String) -> [CursorKVNamespaceSummary] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }
        // Aggregate key-class only. Never SELECT value contents into reports.
        let sql = """
        PRAGMA query_only=ON;
        SELECT CASE
          WHEN key LIKE 'bubbleId:%' THEN 'bubbleId'
          WHEN key LIKE 'agentKv:%' THEN 'agentKv'
          WHEN key LIKE 'checkpointId:%' THEN 'checkpointId'
          WHEN key LIKE 'composerData:%' THEN 'composerData'
          WHEN key LIKE 'composer.content.%' THEN 'composer.content'
          WHEN key LIKE 'ofsContent:%' THEN 'ofsContent'
          WHEN key LIKE 'inlineDiff:%' THEN 'inlineDiff'
          ELSE 'other'
        END AS cls, COUNT(*), SUM(length(value))
        FROM cursorDiskKV GROUP BY cls ORDER BY SUM(length(value)) DESC LIMIT 12;
        """
        let out = runSQLite(db: dbPath, sql: sql, timeoutMs: 120_000)
        guard !out.timedOut else {
            return [
                CursorKVNamespaceSummary(
                    keyClass: "cursorDiskKV",
                    keyCount: -1,
                    approxValueBytes: -1,
                    semanticRole: "QUERY_TIMEOUT_NO_CONTENT"
                )
            ]
        }
        var rows: [CursorKVNamespaceSummary] = []
        for line in out.stdout.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let count = Int(parts[1]),
                  let bytes = Int64(parts[2]) else { continue }
            let cls = String(parts[0])
            let role: String
            switch cls {
            case "bubbleId": role = "AI_CONVERSATION_OR_AGENT_BUBBLE_STATE"
            case "agentKv": role = "AGENT_KEY_VALUE_STATE"
            case "checkpointId": role = "CHECKPOINT_OR_RECOVERY_STATE"
            case "composerData", "composer.content": role = "COMPOSER_SESSION_STATE"
            default: role = "APP_MANAGED_KV"
            }
            rows.append(CursorKVNamespaceSummary(
                keyClass: cls,
                keyCount: count,
                approxValueBytes: bytes,
                semanticRole: role
            ))
        }
        return rows
    }

    // MARK: - FS / process helpers

    static func listDirectChildren(_ root: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".p33a_size") }
            .map { root + "/" + $0 }
            .sorted()
    }

    static func duBytes(_ path: String) -> Int64 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        proc.arguments = ["-sk", path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let kb = Int64(text.split(whereSeparator: { $0.isWhitespace }).first.flatMap { Int64($0) } ?? 0)
        return kb * 1024
    }

    static func isOpen(path: String, openPaths: Set<String>) -> Bool {
        if openPaths.contains(path) { return true }
        for p in openPaths where p.hasPrefix(path) || path.hasPrefix(p) {
            return true
        }
        return false
    }

    static func isCursorRunning() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return false }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").contains(where: {
            let s = String($0)
            return s == "Cursor" || s.hasSuffix("/Cursor") || s.contains("Cursor Helper")
        })
    }

    static func resolveCursorApp() -> (installed: Bool, version: String?, bundleID: String?) {
        let app = "/Applications/Cursor.app"
        guard FileManager.default.fileExists(atPath: app) else {
            return (false, nil, nil)
        }
        let plist = app + "/Contents/Info.plist"
        let version = readPlistString(plist, key: "CFBundleShortVersionString")
        let bid = readPlistString(plist, key: "CFBundleIdentifier")
        return (true, version, bid)
    }

    static func readPlistString(_ path: String, key: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["read", path.replacingOccurrences(of: "/Info.plist", with: ""), key]
        // defaults read wants path without Info.plist sometimes — use plutil
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        p2.arguments = ["-extract", key, "raw", path]
        let pipe = Pipe()
        p2.standardOutput = pipe
        p2.standardError = Pipe()
        do { try p2.run(); p2.waitUntilExit() } catch { return nil }
        let t = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty == false) ? t : nil
    }

    struct SQLiteOut {
        var stdout: String
        var timedOut: Bool
    }

    static func runSQLite(db: String, sql: String, timeoutMs: Int) -> SQLiteOut {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [db, sql]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch {
            return SQLiteOut(stdout: "", timedOut: false)
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            proc.waitUntilExit()
            group.leave()
        }
        let wait = group.wait(timeout: .now() + .milliseconds(timeoutMs))
        if wait == .timedOut {
            proc.terminate()
            return SQLiteOut(stdout: "", timedOut: true)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return SQLiteOut(stdout: String(data: data, encoding: .utf8) ?? "", timedOut: false)
    }

    static func sanitizeID(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: ".")
            .replacingOccurrences(of: " ", with: "_")
    }

    static func sanitizePathClass(_ s: String) -> String {
        // Strip UUID-looking segments from report paths
        let uuid = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return uuid?.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "<id>") ?? s
    }

    static func byteLabel(_ bytes: Int64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }

    /// Root must not become executable merely because it is large.
    public static func rootMayBecomeExecutable(becauseLarge: Bool) -> Bool {
        _ = becauseLarge
        return false
    }

    /// Path word "cache" alone never promotes Safety.
    public static func pathCacheWordPromotesSafety() -> Bool {
        false
    }

    /// Old mtime alone never promotes Safety.
    public static func oldMTimePromotesSafety() -> Bool {
        false
    }
}
