import Foundation

public enum RemoteAuthenticationClass: String, Codable, Sendable, Equatable {
    case anonymous = "ANONYMOUS"
    case existingVendorAuth = "EXISTING_VENDOR_AUTH"
    case authRequired = "AUTH_REQUIRED"
    case unknown = "UNKNOWN"
}

public enum RemoteReacquisitionStatus: String, Codable, Sendable, Equatable {
    case verified = "REACQUIRABLE_VERIFIED"
    case unknown = "REACQUIRABLE_UNKNOWN"
    case authRequired = "AUTH_REQUIRED"
    case rateLimited = "RATE_LIMITED"
    case timeout = "TIMEOUT"
    case remoteUnavailable = "REMOTE_UNAVAILABLE"
    case identityMismatch = "REMOTE_IDENTITY_MISMATCH"
    case accessUnknown = "ACCESS_UNKNOWN"
    case conflicted = "CONFLICTED"
    case notApplicable = "NOT_APPLICABLE"
}

public enum RemoteProofMethod: String, Codable, Sendable, Equatable {
    case hfRevisionAPI = "HF_REVISION_API"
    case hfResolveHEAD = "HF_RESOLVE_HEAD"
    case ollamaManifestGET = "OLLAMA_MANIFEST_GET"
    case mock = "MOCK"
}

public struct RemoteReacquisitionProof: Codable, Sendable, Equatable {
    public var vendor: VendorStorageKind
    public var entityID: String
    public var localIdentity: String
    public var remoteIdentity: String?
    public var remoteRevisionOrDigest: String?
    public var status: RemoteReacquisitionStatus
    public var verifiedAt: Date
    public var freshUntil: Date
    public var authenticationClass: RemoteAuthenticationClass
    public var proofMethod: RemoteProofMethod
    public var requiredObjectsChecked: Int
    public var requiredObjectsVerified: Int
    public var failureReason: String?
    public var confidence: EvidenceConfidence
    public var estimatedRedownloadBytes: Int64?
    public var offlineAvailabilityLost: Bool
    public var reacquisitionRequiresNetwork: Bool
    public var relevantAction: StorageAction
    public var endpointClass: String

    public var isFresh: Bool { Date() < freshUntil }
    public var isStrictVerified: Bool {
        status == .verified && confidence == .verified && isFresh
    }

    public init(
        vendor: VendorStorageKind,
        entityID: String,
        localIdentity: String,
        remoteIdentity: String? = nil,
        remoteRevisionOrDigest: String? = nil,
        status: RemoteReacquisitionStatus,
        verifiedAt: Date = Date(),
        freshUntil: Date,
        authenticationClass: RemoteAuthenticationClass,
        proofMethod: RemoteProofMethod,
        requiredObjectsChecked: Int = 0,
        requiredObjectsVerified: Int = 0,
        failureReason: String? = nil,
        confidence: EvidenceConfidence,
        estimatedRedownloadBytes: Int64? = nil,
        offlineAvailabilityLost: Bool = true,
        reacquisitionRequiresNetwork: Bool = true,
        relevantAction: StorageAction = .vendorNativeCleanup,
        endpointClass: String
    ) {
        self.vendor = vendor
        self.entityID = entityID
        self.localIdentity = localIdentity
        self.remoteIdentity = remoteIdentity
        self.remoteRevisionOrDigest = remoteRevisionOrDigest
        self.status = status
        self.verifiedAt = verifiedAt
        self.freshUntil = freshUntil
        self.authenticationClass = authenticationClass
        self.proofMethod = proofMethod
        self.requiredObjectsChecked = requiredObjectsChecked
        self.requiredObjectsVerified = requiredObjectsVerified
        self.failureReason = failureReason
        self.confidence = confidence
        self.estimatedRedownloadBytes = estimatedRedownloadBytes
        self.offlineAvailabilityLost = offlineAvailabilityLost
        self.reacquisitionRequiresNetwork = reacquisitionRequiresNetwork
        self.relevantAction = relevantAction
        self.endpointClass = endpointClass
    }
}

public struct RemoteNetworkBudget: Codable, Sendable, Equatable {
    public var maxRemoteRequestsPerVendor: Int
    public var maxRemoteRequestsTotal: Int
    public var requestTimeoutSeconds: Double
    public var totalRemoteProofBudgetMs: Int
    public var maxResponseMetadataBytes: Int
    public var maxRetriesPerRequest: Int
    public var freshnessSeconds: Int

    public static let `default` = RemoteNetworkBudget(
        maxRemoteRequestsPerVendor: 8,
        maxRemoteRequestsTotal: 16,
        requestTimeoutSeconds: 4.0,
        totalRemoteProofBudgetMs: 12_000,
        maxResponseMetadataBytes: 512_000,
        maxRetriesPerRequest: 1,
        freshnessSeconds: 900
    )
}

public struct RemoteHTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var cacheKey: String

    public init(method: String = "GET", url: URL, headers: [String: String] = [:], cacheKey: String) {
        self.method = method
        self.url = url
        self.headers = headers
        self.cacheKey = cacheKey
    }
}

public struct RemoteHTTPResponse: Sendable {
    public var statusCode: Int
    public var body: Data
    public var timedOut: Bool
    public var bytesReceived: Int
    public var errorKind: String?

    public init(statusCode: Int, body: Data = Data(), timedOut: Bool = false, bytesReceived: Int? = nil, errorKind: String? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.timedOut = timedOut
        self.bytesReceived = bytesReceived ?? body.count
        self.errorKind = errorKind
    }
}

public protocol RemoteHTTPTransport: Sendable {
    func perform(_ request: RemoteHTTPRequest, timeoutSeconds: Double, maxBytes: Int) -> RemoteHTTPResponse
}

/// Read-only URLSession transport. Never logs Authorization / cookies / tokens.
public struct URLSessionRemoteTransport: RemoteHTTPTransport {
    public init() {}

    public func perform(_ request: RemoteHTTPRequest, timeoutSeconds: Double, maxBytes: Int) -> RemoteHTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeoutSeconds)
        urlRequest.httpMethod = request.method
        for (k, v) in request.headers {
            // Refuse to attach secrets from caller accidentally named token-like — only allow Accept/User-Agent.
            let lower = k.lowercased()
            if lower == "authorization" || lower == "cookie" || lower.contains("token") || lower.contains("api-key") {
                continue
            }
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("AIStorageManager/P3.1.1-read-only", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var captured: RemoteHTTPResponse?
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            defer { sem.signal() }
            if let error = error as NSError? {
                let timedOut = error.code == NSURLErrorTimedOut
                captured = RemoteHTTPResponse(
                    statusCode: 0,
                    body: Data(),
                    timedOut: timedOut,
                    bytesReceived: 0,
                    errorKind: timedOut ? "TIMEOUT" : "NETWORK_ERROR"
                )
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var body = data ?? Data()
            if body.count > maxBytes {
                body = body.prefix(maxBytes)
            }
            captured = RemoteHTTPResponse(statusCode: code, body: body, timedOut: false, bytesReceived: body.count)
        }
        task.resume()
        let wait = sem.wait(timeout: .now() + timeoutSeconds + 1.0)
        if wait == .timedOut {
            task.cancel()
            return RemoteHTTPResponse(statusCode: 0, timedOut: true, errorKind: "TIMEOUT")
        }
        return captured ?? RemoteHTTPResponse(statusCode: 0, timedOut: true, errorKind: "TIMEOUT")
    }
}

public final class MockRemoteHTTPTransport: @unchecked Sendable, RemoteHTTPTransport {
    public var handlers: [String: (RemoteHTTPRequest) -> RemoteHTTPResponse] = [:]
    public var defaultResponse = RemoteHTTPResponse(statusCode: 404, errorKind: "MOCK_DEFAULT")
    public private(set) var calls: [RemoteHTTPRequest] = []

    public init() {}

    public func perform(_ request: RemoteHTTPRequest, timeoutSeconds: Double, maxBytes: Int) -> RemoteHTTPResponse {
        _ = timeoutSeconds
        _ = maxBytes
        calls.append(request)
        if let handler = handlers[request.cacheKey] ?? handlers[request.url.absoluteString] {
            return handler(request)
        }
        return defaultResponse
    }
}

public final class RemoteRequestSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: RemoteHTTPResponse] = [:]
    private var inFlight: [String: [()] ] = [:]
    private var requests = 0
    private var hits = 0
    private var coalesced = 0
    private var bytesReceived = 0
    private var timeouts = 0
    private var perVendor: [String: Int] = [:]
    private let budget: RemoteNetworkBudget
    private let transport: any RemoteHTTPTransport
    private var started = Date()
    private var exhausted = false

    public init(budget: RemoteNetworkBudget = .default, transport: any RemoteHTTPTransport = URLSessionRemoteTransport()) {
        self.budget = budget
        self.transport = transport
    }

    public var stats: (requests: Int, hits: Int, coalesced: Int, bytes: Int, timeouts: Int) {
        lock.lock(); defer { lock.unlock() }
        return (requests, hits, coalesced, bytesReceived, timeouts)
    }

    public var isBudgetExhausted: Bool {
        lock.lock(); defer { lock.unlock() }
        return exhausted || requests >= budget.maxRemoteRequestsTotal
            || Int(Date().timeIntervalSince(started) * 1000) >= budget.totalRemoteProofBudgetMs
    }

    public func request(
        _ request: RemoteHTTPRequest,
        vendor: VendorStorageKind,
        allowRetry: Bool = true
    ) -> RemoteHTTPResponse {
        lock.lock()
        if let hit = cache[request.cacheKey] {
            hits += 1
            lock.unlock()
            return hit
        }
        let vendorKey = vendor.rawValue
        let vendorCount = perVendor[vendorKey, default: 0]
        if exhausted
            || requests >= budget.maxRemoteRequestsTotal
            || vendorCount >= budget.maxRemoteRequestsPerVendor
            || Int(Date().timeIntervalSince(started) * 1000) >= budget.totalRemoteProofBudgetMs {
            exhausted = true
            lock.unlock()
            return RemoteHTTPResponse(statusCode: 0, timedOut: false, errorKind: "REMOTE_BUDGET_EXCEEDED")
        }
        requests += 1
        perVendor[vendorKey, default: 0] += 1
        lock.unlock()

        var response = transport.perform(
            request,
            timeoutSeconds: budget.requestTimeoutSeconds,
            maxBytes: budget.maxResponseMetadataBytes
        )
        if response.timedOut || response.errorKind == "NETWORK_ERROR", allowRetry, budget.maxRetriesPerRequest > 0 {
            response = transport.perform(
                request,
                timeoutSeconds: budget.requestTimeoutSeconds,
                maxBytes: budget.maxResponseMetadataBytes
            )
            lock.lock()
            requests += 1
            perVendor[vendorKey, default: 0] += 1
            lock.unlock()
        }

        lock.lock()
        bytesReceived += response.bytesReceived
        if response.timedOut { timeouts += 1 }
        cache[request.cacheKey] = response
        lock.unlock()
        return response
    }

    public var freshnessSeconds: Int { budget.freshnessSeconds }

    /// Last live stats for reporting (no secrets).
    public static var lastStats: (requests: Int, hits: Int, coalesced: Int, bytes: Int, timeouts: Int)?
}

public enum RemoteReacquisitionProofIndex {
    private static let lock = NSLock()
    private static var byEntity: [String: RemoteReacquisitionProof] = [:]

    public static func reset() {
        lock.lock(); byEntity.removeAll(); lock.unlock()
    }

    public static func store(_ proof: RemoteReacquisitionProof) {
        lock.lock(); byEntity[proof.entityID] = proof; lock.unlock()
    }

    public static func proof(for entityID: String) -> RemoteReacquisitionProof? {
        lock.lock(); defer { lock.unlock() }
        return byEntity[entityID]
    }

    public static func all() -> [RemoteReacquisitionProof] {
        lock.lock(); defer { lock.unlock() }
        return Array(byEntity.values)
    }
}
