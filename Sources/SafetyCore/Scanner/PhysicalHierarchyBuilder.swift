import Foundation

/// Builds a visual physical hierarchy using the existing scanner session.
/// Not a second filesystem truth: measurements go through ScanSessionContext / ReadOnlyStorageScanner.
public enum PhysicalHierarchyBuilder {
    public static func build(
        rootPath: String,
        displayName: String,
        nodeKind: PhysicalNodeKind = .volume,
        scanner: ReadOnlyStorageScanner = ReadOnlyStorageScanner(),
        config: PhysicalHierarchyConfig = .visualDefault,
        onPublication: ((PhysicalStorageNode, PhysicalHierarchyStats, PhysicalHierarchyPublication) -> Void)? = nil
    ) -> (node: PhysicalStorageNode, stats: PhysicalHierarchyStats) {
        let started = Date()
        let state = WalkState(config: config)
        let expanded = PathGlob.expandHome(rootPath)
        ScanSessionContext.current?.performanceTrace.start("session_setup")
        ScanSessionContext.current?.performanceTrace.end("session_setup", ioType: "none", blocking: false)

        let root = walkRoot(
            path: expanded,
            displayName: displayName,
            nodeKind: nodeKind,
            scanner: scanner,
            state: state,
            started: started,
            onPublication: onPublication
        )
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        var stats = makeStats(root: root, elapsedMs: ms)
        if let useful = state.firstUsefulMapMs {
            stats.timeToFirstUsefulMapMs = useful
        }
        onPublication?(root, stats, .complete)
        return (root, stats)
    }

    /// Re-walk a directory and splice it into an existing tree. Read-only.
    public static func expand(
        path: String,
        in root: PhysicalStorageNode,
        scanner: ReadOnlyStorageScanner = ReadOnlyStorageScanner(),
        config: PhysicalHierarchyConfig = .expandDefault
    ) -> PhysicalStorageNode {
        let expanded = PathGlob.expandHome(path)
        var state = WalkState(config: config)
        let rebuilt = walk(
            path: expanded,
            displayName: (expanded as NSString).lastPathComponent,
            nodeKind: .directory,
            depth: 0,
            scanner: scanner,
            state: state,
            timeout: config.rootTimeoutSeconds
        )
        return splice(rebuilt, into: root)
    }

    public static func node(withID id: String, in root: PhysicalStorageNode) -> PhysicalStorageNode? {
        if root.id == id { return root }
        for child in root.children {
            if let hit = node(withID: id, in: child) { return hit }
        }
        return nil
    }

    public static func pathTo(id: String, in root: PhysicalStorageNode) -> [PhysicalStorageNode]? {
        if root.id == id { return [root] }
        for child in root.children {
            if let sub = pathTo(id: id, in: child) {
                return [root] + sub
            }
        }
        return nil
    }

    public static func flatten(_ root: PhysicalStorageNode) -> [PhysicalStorageNode] {
        var out: [PhysicalStorageNode] = [root]
        for child in root.children {
            out.append(contentsOf: flatten(child))
        }
        return out
    }

    /// Parent inclusive == child inclusive sum + exclusive, when all sizes are known.
    /// Restricted/unknown nodes are excluded from the equation rather than treated as zero.
    public static func accountingValid(_ node: PhysicalStorageNode) -> Bool {
        guard validateNode(node) else { return false }
        return node.children.allSatisfy { accountingValid($0) }
    }

    public static func hasDuplicateByteOwnership(_ node: PhysicalStorageNode) -> Bool {
        var seen: [String: String] = [:]
        return duplicateOwner(node, seen: &seen)
    }

    // MARK: - Walk

    private final class WalkState: @unchecked Sendable {
        let lock = NSLock()
        let config: PhysicalHierarchyConfig
        var visited: Set<String> = []
        var nodeCount: Int = 0
        var firstUsefulMapMs: Int?

        init(config: PhysicalHierarchyConfig) {
            self.config = config
        }

        func claim(_ path: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if visited.contains(path) { return false }
            visited.insert(path)
            nodeCount += 1
            return true
        }

        func incrementNode() {
            lock.lock(); nodeCount += 1; lock.unlock()
        }

        var currentNodeCount: Int {
            lock.lock(); defer { lock.unlock() }
            return nodeCount
        }
    }

    private static func walkRoot(
        path: String,
        displayName: String,
        nodeKind: PhysicalNodeKind,
        scanner: ReadOnlyStorageScanner,
        state: WalkState,
        started: Date,
        onPublication: ((PhysicalStorageNode, PhysicalHierarchyStats, PhysicalHierarchyPublication) -> Void)?
    ) -> PhysicalStorageNode {
        let canonical = (path as NSString).standardizingPath
        let id = "phys:" + canonical
        let session = ScanSessionContext.current

        if HardSafetyGates.isHardBlocked(path: canonical) {
            return restrictedNode(id: id, path: canonical, name: displayName, depth: 0, reason: "HARD_BLOCKED")
        }
        _ = state.claim(canonical)

        session?.performanceTrace.start("root_direct_child_enumeration")
        let listed = listedChildNames(at: canonical)
        session?.performanceTrace.end(
            "root_direct_child_enumeration",
            nodeCount: listed?.count ?? 0,
            ioType: "directory_enumeration",
            blocking: true
        )

        // Root du must not block first map. Start it, keep going.
        session?.performanceTrace.start("root_measurement")
        if let session {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = session.measure(
                    path: canonical,
                    caller: "PhysicalHierarchyBuilder.root",
                    timeoutSeconds: state.config.rootTimeoutSeconds,
                    mode: "bounded_du"
                )
                session.performanceTrace.end("root_measurement", ioType: "du", blocking: false)
            }
        }

        let childTimeout = state.config.childTimeoutSeconds
        session?.performanceTrace.start("child_measurement")
        let shallow = measureDirectChildren(
            parentPath: canonical,
            listing: listed,
            scanner: scanner,
            state: state,
            timeout: childTimeout
        )
        session?.performanceTrace.end(
            "child_measurement",
            nodeCount: shallow.count,
            cacheHits: session?.cacheHits ?? 0,
            cacheMisses: session?.cacheMisses ?? 0,
            ioType: "du",
            timeoutCount: session?.duTimeoutCount() ?? 0,
            blocking: true
        )

        var root = assembleRoot(
            id: id,
            canonical: canonical,
            displayName: displayName,
            nodeKind: nodeKind,
            children: shallow,
            rootMeasurement: session?.measurement(for: canonical)
        )
        publishIfUseful(root, started: started, state: state, kind: .firstUsefulMap, onPublication: onPublication)
        publishIfUseful(root, started: started, state: state, kind: .directChildrenMeasured, onPublication: onPublication)

        session?.performanceTrace.start("deep_hierarchy")
        let expandedChildren = expandChildren(
            shallow,
            parentPath: canonical,
            scanner: scanner,
            state: state
        )
        session?.performanceTrace.end("deep_hierarchy", nodeCount: state.currentNodeCount, ioType: "du", blocking: true)

        let finishedRoot = session?.waitForMeasurement(
            path: canonical,
            timeoutSeconds: state.config.rootTimeoutSeconds
        )
        root = assembleRoot(
            id: id,
            canonical: canonical,
            displayName: displayName,
            nodeKind: nodeKind,
            children: expandedChildren,
            rootMeasurement: finishedRoot ?? session?.measurement(for: canonical)
        )
        return root
    }

    private static func listedChildNames(at parentPath: String) -> [String]? {
        let fm = FileManager.default
        let started = Date()
        do {
            let names = try fm.contentsOfDirectory(atPath: parentPath)
                .filter { $0 != "." && $0 != ".." }
                .sorted()
            ScanSessionContext.current?.recordDirectoryEnumeration(
                at: parentPath,
                childCount: names.count,
                caller: "PhysicalHierarchyBuilder",
                durationMs: Int(Date().timeIntervalSince(started) * 1000)
            )
            return names
        } catch {
            ScanSessionContext.current?.recordDirectoryEnumeration(
                at: parentPath,
                childCount: 0,
                caller: "PhysicalHierarchyBuilder",
                durationMs: Int(Date().timeIntervalSince(started) * 1000)
            )
            return nil
        }
    }

    private static func measureDirectChildren(
        parentPath: String,
        listing: [String]?,
        scanner: ReadOnlyStorageScanner,
        state: WalkState,
        timeout: Double
    ) -> [PhysicalStorageNode] {
        guard let names = listing else {
            return [
                restrictedNode(
                    id: "phys:\(parentPath)/#restricted",
                    path: parentPath,
                    name: "Restricted / Not Scanned",
                    depth: 1,
                    reason: "PERMISSION_DENIED"
                )
            ]
        }
        let capped = Array(names.prefix(state.config.maxChildrenPerDirectory))
        var collected: [String: PhysicalStorageNode] = [:]
        let collectLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: capped.count) { index in
            let name = capped[index]
            let childPath = (parentPath as NSString).appendingPathComponent(name)
            let node = walk(
                path: childPath,
                displayName: name,
                nodeKind: .directory,
                depth: 1,
                scanner: scanner,
                state: state,
                timeout: timeout,
                descend: false
            )
            collectLock.lock()
            collected[name] = node
            collectLock.unlock()
        }
        var measured = capped.compactMap { collected[$0] }
        measured.sort { lhs, rhs in
            if lhs.bytesKnown != rhs.bytesKnown { return lhs.bytesKnown && !rhs.bytesKnown }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return groupSmallItems(measured, parentPath: parentPath, depth: 1)
    }

    private static func expandChildren(
        _ children: [PhysicalStorageNode],
        parentPath: String,
        scanner: ReadOnlyStorageScanner,
        state: WalkState
    ) -> [PhysicalStorageNode] {
        _ = parentPath
        return children.map { child in
            guard child.isDirectory, !child.isPackage, !child.isSymlink, !child.isRestricted, !child.isAggregate else {
                return child
            }
            if state.currentNodeCount >= state.config.maxNodes { return child }
            if 1 >= state.config.maxDepth { return child }
            var copy = child
            copy.children = enumerateChildren(
                parentPath: child.canonicalPath,
                parentBytes: child.bytes,
                parentBytesKnown: child.bytesKnown,
                depth: 2,
                scanner: scanner,
                state: state
            )
            let childSum = copy.children.reduce(Int64(0)) { partial, node in
                guard node.bytesKnown else { return partial }
                return partial + node.bytes
            }
            if copy.bytesKnown, copy.children.allSatisfy(\.bytesKnown) {
                copy.exclusiveKnown = true
                copy.exclusiveBytes = max(0, copy.bytes - childSum)
            }
            return copy
        }
    }

    private static func assembleRoot(
        id: String,
        canonical: String,
        displayName: String,
        nodeKind: PhysicalNodeKind,
        children: [PhysicalStorageNode],
        rootMeasurement: SizeMeasurement?
    ) -> PhysicalStorageNode {
        let bytesKnown = rootMeasurement?.isKnown == true && rootMeasurement?.quality != .unknown
        let bytes = bytesKnown ? (rootMeasurement?.bytes ?? 0) : 0
        let childSum = children.reduce(Int64(0)) { partial, child in
            guard child.bytesKnown else { return partial }
            return partial + child.bytes
        }
        let exclusiveKnown = bytesKnown && children.allSatisfy(\.bytesKnown)
        return PhysicalStorageNode(
            id: id,
            canonicalPath: canonical,
            displayName: displayName.isEmpty ? (canonical as NSString).lastPathComponent : displayName,
            nodeKind: nodeKind,
            bytes: bytes,
            bytesKnown: bytesKnown,
            exclusiveBytes: exclusiveKnown ? max(0, bytes - childSum) : 0,
            exclusiveKnown: exclusiveKnown,
            children: children,
            depth: 0,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            measurementQuality: rootMeasurement?.quality ?? .unknown,
            measurementReason: rootMeasurement?.reason ?? "ROOT_MEASUREMENT_PENDING"
        )
    }

    private static func publishIfUseful(
        _ root: PhysicalStorageNode,
        started: Date,
        state: WalkState,
        kind: PhysicalHierarchyPublication,
        onPublication: ((PhysicalStorageNode, PhysicalHierarchyStats, PhysicalHierarchyPublication) -> Void)?
    ) {
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        let useful = root.children.contains { !$0.displayName.isEmpty }
            && (accounting.reportMappedBytes > 0 || accounting.coverage == .unknown)
            && accounting.accountingValid
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if useful, state.firstUsefulMapMs == nil {
            state.firstUsefulMapMs = ms
        }
        var stats = makeStats(root: root, elapsedMs: ms)
        stats.timeToFirstUsefulMapMs = state.firstUsefulMapMs ?? ms
        if kind == .firstUsefulMap, !useful { return }
        onPublication?(root, stats, kind)
    }

    private static func walk(
        path: String,
        displayName: String,
        nodeKind: PhysicalNodeKind,
        depth: Int,
        scanner: ReadOnlyStorageScanner,
        state: WalkState,
        timeout: Double,
        descend: Bool = true
    ) -> PhysicalStorageNode {
        let canonical = (path as NSString).standardizingPath
        let id = "phys:" + canonical

        if HardSafetyGates.isHardBlocked(path: canonical) {
            return restrictedNode(
                id: id,
                path: canonical,
                name: displayName,
                depth: depth,
                reason: "HARD_BLOCKED"
            )
        }

        if !state.claim(canonical) {
            return PhysicalStorageNode(
                id: id + "#cycle",
                canonicalPath: canonical,
                displayName: displayName,
                nodeKind: .symlink,
                bytes: 0,
                bytesKnown: false,
                depth: depth,
                isDirectory: false,
                isFile: false,
                isPackage: false,
                isSymlink: true,
                measurementReason: "SYMLINK_OR_CYCLE_SKIPPED"
            )
        }

        guard let scanned = measure(path: canonical, scanner: scanner, timeout: timeout, depth: depth) else {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: canonical, isDirectory: &isDir)
            if !exists {
                return restrictedNode(id: id, path: canonical, name: displayName, depth: depth, reason: "PATH_NOT_PRESENT")
            }
            return restrictedNode(id: id, path: canonical, name: displayName, depth: depth, reason: "MEASUREMENT_UNAVAILABLE")
        }

        let kind: PhysicalNodeKind
        if scanned.isSymlink {
            kind = .symlink
        } else if scanned.isPackage {
            kind = .package
        } else if scanned.isDirectory {
            kind = depth == 0 ? nodeKind : .directory
        } else {
            kind = .file
        }

        let bytesKnown = scanned.measurementKnown && scanned.measurementQuality != .unknown
        let bytes = bytesKnown ? scanned.logicalBytes : 0

        let shouldDescend =
            descend
            && scanned.isDirectory
            && !scanned.isSymlink
            && (state.config.expandPackages || !scanned.isPackage)
            && !state.config.followSymlinks
            && depth < state.config.maxDepth
            && state.currentNodeCount < state.config.maxNodes

        var children: [PhysicalStorageNode] = []
        if shouldDescend {
            children = enumerateChildren(
                parentPath: canonical,
                parentBytes: bytes,
                parentBytesKnown: bytesKnown,
                depth: depth + 1,
                scanner: scanner,
                state: state
            )
        }

        let childSum = children.reduce(Int64(0)) { partial, child in
            guard child.bytesKnown else { return partial }
            return partial + child.bytes
        }
        let exclusiveKnown = bytesKnown && children.allSatisfy(\.bytesKnown)
        let exclusive = exclusiveKnown ? max(0, bytes - childSum) : 0

        return PhysicalStorageNode(
            id: id,
            canonicalPath: canonical,
            displayName: displayName.isEmpty ? (canonical as NSString).lastPathComponent : displayName,
            nodeKind: kind,
            bytes: bytes,
            bytesKnown: bytesKnown,
            exclusiveBytes: exclusive,
            exclusiveKnown: exclusiveKnown,
            children: children,
            depth: depth,
            isDirectory: scanned.isDirectory,
            isFile: !scanned.isDirectory && !scanned.isSymlink,
            isPackage: scanned.isPackage,
            isSymlink: scanned.isSymlink,
            measurementQuality: scanned.measurementQuality,
            measurementReason: scanned.measurementReason
        )
    }

    private static func enumerateChildren(
        parentPath: String,
        parentBytes: Int64,
        parentBytesKnown: Bool,
        depth: Int,
        scanner: ReadOnlyStorageScanner,
        state: WalkState
    ) -> [PhysicalStorageNode] {
        let fm = FileManager.default
        let started = Date()
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: parentPath)
        } catch {
            ScanSessionContext.current?.recordDirectoryEnumeration(
                at: parentPath,
                childCount: 0,
                caller: "PhysicalHierarchyBuilder",
                durationMs: Int(Date().timeIntervalSince(started) * 1000)
            )
            return [
                restrictedNode(
                    id: "phys:\(parentPath)/#restricted",
                    path: parentPath,
                    name: "Restricted / Not Scanned",
                    depth: depth,
                    reason: "PERMISSION_DENIED"
                )
            ]
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        ScanSessionContext.current?.recordDirectoryEnumeration(
            at: parentPath,
            childCount: names.count,
            caller: "PhysicalHierarchyBuilder",
            durationMs: ms
        )

        var measured: [PhysicalStorageNode] = []
        let timeout = depth <= 1 ? state.config.childTimeoutSeconds : Double(ScanSessionContext.current?.budget.duTimeoutMs ?? 3000) / 1000.0
        let sortedNames = names.filter { $0 != "." && $0 != ".." }.sorted()
        for name in sortedNames {
            if state.currentNodeCount >= state.config.maxNodes { break }
            if measured.count >= state.config.maxChildrenPerDirectory { break }
            let childPath = (parentPath as NSString).appendingPathComponent(name)
            if !state.config.followSymlinks, (try? fm.destinationOfSymbolicLink(atPath: childPath)) != nil {
                let linkNode = walk(
                    path: childPath,
                    displayName: name,
                    nodeKind: .symlink,
                    depth: depth,
                    scanner: scanner,
                    state: state,
                    timeout: timeout
                )
                measured.append(linkNode)
                continue
            }
            let child = walk(
                path: childPath,
                displayName: name,
                nodeKind: .directory,
                depth: depth,
                scanner: scanner,
                state: state,
                timeout: timeout
            )
            measured.append(child)
        }

        measured.sort { lhs, rhs in
            if lhs.bytesKnown != rhs.bytesKnown { return lhs.bytesKnown && !rhs.bytesKnown }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        let listedCount = min(sortedNames.count, state.config.maxChildrenPerDirectory)
        let omitted = sortedNames.count - listedCount
        if omitted > 0, parentBytesKnown {
            let measuredSum = measured.reduce(Int64(0)) { $0 + ($1.bytesKnown ? $1.bytes : 0) }
            let remainder = max(0, parentBytes - measuredSum)
            let otherChildren = Array(measured.suffix(from: min(measured.count, 12)))
            let visible = Array(measured.prefix(12))
            let other = PhysicalStorageNode(
                id: "phys:\(parentPath)/#other",
                canonicalPath: parentPath + "/#other",
                displayName: "Other smaller items",
                nodeKind: .otherAggregate,
                bytes: remainder > 0 ? remainder : otherChildren.reduce(0) { $0 + ($1.bytesKnown ? $1.bytes : 0) },
                bytesKnown: true,
                exclusiveBytes: 0,
                exclusiveKnown: true,
                children: otherChildren.isEmpty ? [] : otherChildren,
                depth: depth,
                isDirectory: true,
                isFile: false,
                isPackage: false,
                isSymlink: false,
                isAggregate: true,
                measurementQuality: .bounded,
                measurementReason: "GROUPED_SMALL_ITEMS"
            )
            return visible + [other]
        }

        return groupSmallItems(measured, parentPath: parentPath, depth: depth)
    }

    private static func groupSmallItems(
        _ nodes: [PhysicalStorageNode],
        parentPath: String,
        depth: Int
    ) -> [PhysicalStorageNode] {
        let known = nodes.filter(\.bytesKnown)
        let unknown = nodes.filter { !$0.bytesKnown }
        let total = known.reduce(Int64(0)) { $0 + $1.bytes }
        guard known.count >= 8, total > 0 else { return nodes }
        let threshold = max(total / 100, 1)
        var large: [PhysicalStorageNode] = []
        var small: [PhysicalStorageNode] = []
        for node in known {
            if node.bytes >= threshold || large.count < 6 {
                large.append(node)
            } else {
                small.append(node)
            }
        }
        guard small.count >= 3 else { return nodes }
        let otherBytes = small.reduce(Int64(0)) { $0 + $1.bytes }
        let other = PhysicalStorageNode(
            id: "phys:\(parentPath)/#other",
            canonicalPath: parentPath + "/#other",
            displayName: "Other smaller items",
            nodeKind: .otherAggregate,
            bytes: otherBytes,
            bytesKnown: true,
            exclusiveBytes: 0,
            exclusiveKnown: true,
            children: small,
            depth: depth,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            isAggregate: true,
            measurementQuality: .bounded,
            measurementReason: "GROUPED_SMALL_ITEMS"
        )
        return large + unknown + [other]
    }

    private static func measure(
        path: String,
        scanner: ReadOnlyStorageScanner,
        timeout: Double,
        depth: Int
    ) -> ScannedNode? {
        if let session = ScanSessionContext.current {
            _ = session.measure(
                path: path,
                caller: "PhysicalHierarchyBuilder",
                timeoutSeconds: timeout,
                mode: "bounded_du"
            )
            return session.getOrScanNode(path: path, scanner: scanner, caller: "PhysicalHierarchyBuilder")
        }
        return scanner.scanNode(path: path, caller: "PhysicalHierarchyBuilder")
    }

    private static func restrictedNode(
        id: String,
        path: String,
        name: String,
        depth: Int,
        reason: String
    ) -> PhysicalStorageNode {
        PhysicalStorageNode(
            id: id,
            canonicalPath: path,
            displayName: name,
            nodeKind: .restricted,
            bytes: 0,
            bytesKnown: false,
            depth: depth,
            isDirectory: true,
            isFile: false,
            isPackage: false,
            isSymlink: false,
            isRestricted: true,
            measurementQuality: .unknown,
            measurementReason: reason
        )
    }

    private static func splice(_ rebuilt: PhysicalStorageNode, into root: PhysicalStorageNode) -> PhysicalStorageNode {
        if root.canonicalPath == rebuilt.canonicalPath || root.id == rebuilt.id {
            var copy = rebuilt
            copy.depth = root.depth
            return copy
        }
        var copy = root
        copy.children = root.children.map { splice(rebuilt, into: $0) }
        return copy
    }

    private static func validateNode(_ node: PhysicalStorageNode) -> Bool {
        if node.isRestricted || !node.bytesKnown {
            return true
        }
        let knownChildren = node.children.filter(\.bytesKnown)
        let sum = knownChildren.reduce(Int64(0)) { $0 + $1.bytes }
        if node.children.allSatisfy(\.bytesKnown), sum > node.bytes {
            return false
        }
        if node.exclusiveKnown, node.exclusiveBytes + sum != node.bytes {
            return false
        }
        if node.exclusiveBytes < 0 { return false }
        return true
    }

    private static func duplicateOwner(_ node: PhysicalStorageNode, seen: inout [String: String]) -> Bool {
        if !node.isAggregate, !node.canonicalPath.contains("#") {
            if let existing = seen[node.canonicalPath], existing != node.id {
                return true
            }
            seen[node.canonicalPath] = node.id
        }
        for child in node.children {
            if duplicateOwner(child, seen: &seen) { return true }
        }
        return false
    }

    private static func makeStats(root: PhysicalStorageNode, elapsedMs: Int) -> PhysicalHierarchyStats {
        let all = flatten(root)
        let maxDepth = all.map(\.depth).max() ?? 0
        let fanout = all.map(\.children.count).max() ?? 0
        let accounting = PhysicalMapAccountingResolver.resolve(for: root)
        return PhysicalHierarchyStats(
            physicalNodeCount: all.count,
            maxDepth: maxDepth,
            largestFanout: fanout,
            representedBytes: accounting.reportMappedBytes,
            restrictedNodeCount: all.filter(\.isRestricted).count,
            unknownByteNodeCount: all.filter { !$0.bytesKnown }.count,
            accountingValid: accounting.accountingValid && !hasDuplicateByteOwnership(root),
            duplicateByteOwnership: hasDuplicateByteOwnership(root),
            timeToFirstHierarchyMs: elapsedMs,
            timeToFirstUsefulMapMs: elapsedMs
        )
    }
}
