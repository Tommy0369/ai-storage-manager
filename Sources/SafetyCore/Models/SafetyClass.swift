import Foundation

public enum SafetyClass: String, Codable, Sendable, Comparable {
    case green = "GREEN"
    case yellow = "YELLOW"
    case red = "RED"
    case unknown = "UNKNOWN"

    /// Lower is more restrictive. Used only for demotion, never promotion.
    private var rank: Int {
        switch self {
        case .red: return 0
        case .unknown: return 1
        case .yellow: return 2
        case .green: return 3
        }
    }

    public static func < (lhs: SafetyClass, rhs: SafetyClass) -> Bool {
        lhs.rank < rhs.rank
    }

    public func demoted(to lower: SafetyClass) -> SafetyClass {
        min(self, lower)
    }
}

public struct SafetyScore: Codable, Sendable, Equatable {
    public let value: Int
    public let scale: Int

    public init(value: Int, scale: Int = 100) {
        self.value = min(max(value, 0), scale)
        self.scale = scale
    }

    /// Ranking aid only. Never a probability of safety. Never promotes class.
    public var isRankingOnly: Bool { true }
}
