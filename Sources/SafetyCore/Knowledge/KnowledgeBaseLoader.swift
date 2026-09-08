import Foundation

public enum KnowledgeBaseLoaderError: Error {
    case resourceMissing
    case decodeFailed(String)
}

public struct KnowledgeBaseLoader {
    public init() {}

    public func loadBundled() throws -> KnowledgeBaseDocument {
        let urls = [
            Bundle.module.url(forResource: "compiled_rules_v0.1", withExtension: "json", subdirectory: "Resources/knowledge"),
            Bundle.module.url(forResource: "compiled_rules_v0.1", withExtension: "json", subdirectory: "knowledge"),
            Bundle.module.url(forResource: "compiled_rules_v0.1", withExtension: "json"),
        ]
        guard let url = urls.compactMap({ $0 }).first else {
            throw KnowledgeBaseLoaderError.resourceMissing
        }
        return try load(from: url)
    }

    public func load(from url: URL) throws -> KnowledgeBaseDocument {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(KnowledgeBaseDocument.self, from: data)
        } catch {
            throw KnowledgeBaseLoaderError.decodeFailed(String(describing: error))
        }
    }

    /// Vendor-specific (exact) rules win over generic path rules.
    public func rulesSortedForEvaluation(_ document: KnowledgeBaseDocument) -> [SafetyRule] {
        document.rules.sorted { lhs, rhs in
            if lhs.evaluationLayer != rhs.evaluationLayer {
                return lhs.evaluationLayer < rhs.evaluationLayer
            }
            let l = globSpecificity(lhs.match.path)
            let r = globSpecificity(rhs.match.path)
            return l > r
        }
    }

    public func globSpecificity(_ pattern: String) -> Int {
        pattern
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .count
    }
}
