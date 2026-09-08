import Foundation

public struct DockerDetectionReport: Codable, Sendable, Equatable {
    public var dockerAppExists: Bool
    public var dockerCLIAvailable: Bool
    public var dockerProcessDetected: Bool
    public var dockerContext: String?
    public var dockerRootDir: String?
    public var storageLocations: [String]
    public var dfRaw: String?
    public var detectedEntityIDs: [String]
    public var totalLogicalBytes: Int64
    public var unknowns: [String]
}

public struct DockerProbe {
    public init() {}

    public func probe(home: String) -> DockerDetectionReport {
        var unknowns: [String] = []
        let app = FileManager.default.fileExists(atPath: "/Applications/Docker.app")
        let cli = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/docker")
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/docker")
            || FileManager.default.isExecutableFile(atPath: "/usr/bin/docker")
        let dockerBin = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "/usr/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }

        var process = false
        switch ProcessCheck().isRunning(executableNames: ["com.docker.backend", "Docker", "dockerd"]) {
        case .true: process = true
        case .false: process = false
        case .unknown: unknowns.append("process_state")
        }

        var locations: [String] = []
        let candidates = [
            "\(home)/Library/Containers/com.docker.docker",
            "\(home)/Library/Containers/com.docker.docker/Data",
            "\(home)/Library/Group Containers/group.com.docker",
            "\(home)/.docker",
            "\(home)/Library/Containers/com.docker.helper",
        ]
        for p in candidates where FileManager.default.fileExists(atPath: p) {
            locations.append(p)
        }

        var context: String?
        var rootDir: String?
        var dfRaw: String?
        if let bin = dockerBin {
            context = run(bin, ["context", "show"])
            rootDir = run(bin, ["info", "--format", "{{.DockerRootDir}}"])
            dfRaw = run(bin, ["system", "df"])
            if let rootDir, FileManager.default.fileExists(atPath: rootDir), !locations.contains(rootDir) {
                locations.append(rootDir)
            }
        } else if !cli {
            unknowns.append("docker_cli")
        }

        return DockerDetectionReport(
            dockerAppExists: app,
            dockerCLIAvailable: dockerBin != nil,
            dockerProcessDetected: process,
            dockerContext: context,
            dockerRootDir: rootDir,
            storageLocations: locations,
            dfRaw: dfRaw,
            detectedEntityIDs: [],
            totalLogicalBytes: 0,
            unknowns: unknowns
        )
    }

    func run(_ bin: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

public struct DockerDetector: EntityDetector {
    public let domain = "Docker"
    public let bucket = SystemDataBucket.developer
    public var probe: DockerProbe

    public init(probe: DockerProbe = DockerProbe()) {
        self.probe = probe
    }

    public func detect(home: String, scanner: ReadOnlyStorageScanner) -> [DetectedEntity] {
        let report = probe.probe(home: home)
        var items: [DetectedEntity] = []
        let paths: [(String, String, EntityKind)] = [
            ("docker.desktop_data", "\(home)/Library/Containers/com.docker.docker/Data", .dockerCache),
            ("docker.desktop_container", "\(home)/Library/Containers/com.docker.docker", .dockerCache),
            ("docker.group_container", "\(home)/Library/Group Containers/group.com.docker", .dockerCache),
            ("docker.dot_docker", "\(home)/.docker", .dockerCache),
            ("docker.images", "\(home)/.docker/images", .dockerImage),
            ("docker.containers_dir", "\(home)/.docker/containers", .dockerContainer),
            ("docker.volumes_dir", "\(home)/.docker/volumes", .dockerVolume),
            ("docker.build_cache", "\(home)/.docker/buildx", .dockerCache),
            ("docker.vm_disk", "\(home)/Library/Containers/com.docker.docker/Data/vms", .dockerCache),
        ]
        for p in paths {
            if let n = node(id: p.0, kind: p.2, category: "DEVELOPER", sub: "DOCKER", path: p.1, scanner: scanner, bucket: bucket, domain: domain, processes: ["com.docker.backend", "Docker"]) {
                items.append(n)
            }
        }
        if let root = report.dockerRootDir, FileManager.default.fileExists(atPath: root) {
            if let n = node(id: "docker.engine_root", kind: .dockerCache, category: "DEVELOPER", sub: "DOCKER", path: root, scanner: scanner, bucket: bucket, domain: domain) {
                items.append(n)
            }
        }
        items.append(DetectedEntity(
            entity: StorageEntity(
                id: "docker.volumes",
                kind: .dockerVolume,
                category: "DEVELOPER",
                subcategory: "DOCKER",
                displayName: "Docker Volumes",
                path: "entity://docker/volumes",
                logicalBytes: 0,
                ownerHint: report.dfRaw
            ),
            bucket: bucket,
            domain: domain,
            associatedProcesses: ["Docker"],
            identified: true
        ))
        return items
    }
}
