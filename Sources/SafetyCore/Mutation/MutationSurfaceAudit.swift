import Foundation

/// Static audit of repository mutation surface. P2.1 allows authorized executor only.
public enum MutationSurfaceAudit {
    private static let forbiddenPatterns: [(String, String)] = [
        ("FileManager.default.removeItem", "FILE_MANAGER_REMOVE"),
        ("FileManager.default.trashItem", "FILE_MANAGER_TRASH"),
        ("removeItem(at:", "REMOVE_ITEM"),
        ("moveItem(at:", "MOVE_ITEM"),
        (".copyItem(at:", "COPY_ITEM_EXEC"),
        ("Process()", "PROCESS_SPAWN"),
        ("executableURL = URL(fileURLWithPath: \"/bin/rm\")", "RAW_RM"),
        ("executableURL = URL(fileURLWithPath: \"/bin/mv\")", "RAW_MV"),
        ("NSWorkspace.shared.recycle", "NSWORKSPACE_RECYCLE"),
        ("startEvicting", "FILE_PROVIDER_EVICT"),
    ]

    private static let observationOnlyPaths: Set<String> = [
        "Sources/SafetyCore/Evidence/EvidenceSnapshots.swift",
        "Sources/SafetyCore/Mutation/MutationSurfaceAudit.swift",
        "Tests/",
    ]

    private static let authorizedExecutorPaths: Set<String> = [
        "Sources/SafetyCore/Mutation/FirstMutatingExecutor.swift",
    ]

    /// Software-install restore (Ollama only). Not a cleanup executor.
    private static let authorizedSoftwareInstallPaths: Set<String> = [
        "Sources/SafetyCore/Mutation/OllamaManagementRestoreInstaller.swift",
    ]

    private static let mutationCategories: Set<String> = [
        "FILE_MANAGER_REMOVE", "FILE_MANAGER_TRASH", "REMOVE_ITEM", "MOVE_ITEM",
        "RAW_RM", "RAW_MV", "NSWORKSPACE_RECYCLE", "FILE_PROVIDER_EVICT",
    ]

    public static func audit(repositoryRoot: String = FileManager.default.currentDirectoryPath) -> MutationSurfaceAuditReport {
        let root = URL(fileURLWithPath: repositoryRoot)
        let sources = root.appendingPathComponent("Sources")
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                files.append(url)
            }
        }

        var findings: [MutationSurfaceFinding] = []
        var authorizedImpls = 0
        var unauthorizedImpls = 0

        for file in files {
            let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let isAuthorizedExecutor = authorizedExecutorPaths.contains(rel)
            let isAuthorizedSoftwareInstall = authorizedSoftwareInstallPaths.contains(rel)
            let isObservationOnly = observationOnlyPaths.contains(where: { rel.hasPrefix($0) || rel.contains($0) })
            if isObservationOnly { continue }
            // Install restore mutations are allowlisted separately from cleanup executor count.
            if isAuthorizedSoftwareInstall { continue }

            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (pattern, category) in forbiddenPatterns {
                for (idx, line) in lines.enumerated() {
                    let s = String(line)
                    if s.contains("//") && s.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                    if !s.contains(pattern) { continue }
                    let isObservation = s.contains("lsof") || s.contains("ps") || s.contains("ProcessTableSnapshot")
                        || s.contains("OpenFileSnapshot") || s.contains("RuntimeObservation")
                    if isObservation { continue }
                    if category == "PROCESS_SPAWN", s.contains("lsof") || s.contains("ps") || s.contains("du") {
                        continue
                    }
                    if category == "COPY_ITEM_EXEC", !s.contains("mutates: true") {
                        continue
                    }
                    if !mutationCategories.contains(category) { continue }

                    findings.append(MutationSurfaceFinding(
                        file: rel,
                        pattern: pattern,
                        line: idx + 1,
                        category: category
                    ))
                    if isAuthorizedExecutor {
                        authorizedImpls += 1
                    } else {
                        unauthorizedImpls += 1
                    }
                }
            }
        }

        let executorImplemented = authorizedImpls > 0
        return MutationSurfaceAuditReport(
            scannedFiles: files.count,
            findings: findings.sorted { $0.file < $1.file },
            actualMutationImplementations: authorizedImpls,
            executorImplemented: executorImplemented,
            auditPassed: unauthorizedImpls == 0 && authorizedImpls <= 1
        )
    }
}
