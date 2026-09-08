import Foundation

/// Central localization resolver. One catalog → localized string.
/// Views must not switch on language; call `L10n.t`.
public enum L10n {
    private static let lock = NSLock()
    private static var overrideLanguage: AppLanguage = .system
    private static var catalog: [String: [String: String]] = loadCatalog()

    public static var productionKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(catalog.keys).sorted()
    }

    public static func setOverride(_ language: AppLanguage) {
        lock.lock(); defer { lock.unlock() }
        overrideLanguage = language
    }

    public static func currentLanguage() -> AppLanguage {
        lock.lock(); defer { lock.unlock() }
        return overrideLanguage
    }

    public static func resolvedLocale(for language: AppLanguage = currentLanguage()) -> Locale {
        if let id = language.localeIdentifier {
            return Locale(identifier: id)
        }
        if let preferred = Locale.preferredLanguages.first {
            return Locale(identifier: preferred)
        }
        return Locale.current
    }

    public static func catalogLocaleID(for language: AppLanguage = currentLanguage()) -> String {
        if let id = language.localeIdentifier {
            return normalizeCatalogID(id)
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return bestCatalogMatch(for: preferred)
    }

    /// Translate a semantic key. Missing keys return the key (audited as defect).
    public static func t(_ key: String, language: AppLanguage? = nil, _ args: CVarArg...) -> String {
        let lang = language ?? currentLanguage()
        let localeID = language.map { catalogLocaleID(for: $0) } ?? catalogLocaleID(for: lang)
        lock.lock()
        let entry = catalog[key]
        lock.unlock()
        let template: String
        if let entry {
            template = entry[localeID] ?? entry["en"] ?? key
        } else {
            template = key
        }
        if args.isEmpty { return template }
        return String(format: template, locale: resolvedLocale(for: lang), arguments: args)
    }

    public static func hasKey(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return catalog[key] != nil
    }

    public static func translation(key: String, localeID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return catalog[key]?[normalizeCatalogID(localeID)]
    }

    public static func coverage(for localeID: String) -> LocalizationLocaleCoverage {
        let id = normalizeCatalogID(localeID)
        lock.lock()
        let keys = Array(catalog.keys)
        var translated = 0
        var fallback = 0
        var missing = 0
        for key in keys {
            guard let entry = catalog[key] else { missing += 1; continue }
            guard let value = entry[id], !value.isEmpty else {
                missing += 1
                continue
            }
            if id != "en", value == entry["en"] {
                // Identical to English may be intentional (product name fragments) —
                // count as translated for coverage; safety audit checks meaning separately.
                translated += 1
                if looksLikeUntranslatedEnglish(key: key, value: value, en: entry["en"] ?? "") {
                    fallback += 1
                }
            } else {
                translated += 1
            }
        }
        lock.unlock()
        let total = keys.count
        let percent = total == 0 ? 100.0 : (Double(translated) / Double(total)) * 100.0
        return LocalizationLocaleCoverage(
            localeID: id,
            totalKeys: total,
            translatedKeys: translated,
            missingKeys: missing,
            fallbackKeys: fallback,
            coveragePercent: percent
        )
    }

    private static func looksLikeUntranslatedEnglish(key: String, value: String, en: String) -> Bool {
        guard value == en else { return false }
        // Proper nouns / short shared tokens are OK
        let allowed = ["Ollama", "Chrome", "Cursor", "Claude", "Info", "Plan", "Custom", "Cloud", "Ready"]
        if allowed.contains(value) { return false }
        if value.count <= 3 { return false }
        // Keys that are expected identical
        if key.contains("entity.ollama") || key.contains("entity.hf") { return false }
        return value.range(of: "[\\u3040-\\u30ff\\u3400-\\u9fff\\uac00-\\ud7af]", options: .regularExpression) == nil
            && value == en
            && !key.hasPrefix("navigation.plan") // "Plan" shared
    }

    private static func normalizeCatalogID(_ id: String) -> String {
        if id.hasPrefix("zh-Hans") || id == "zh-CN" || id == "zh" { return "zh-Hans" }
        if id.hasPrefix("zh-Hant") || id == "zh-TW" || id == "zh-HK" { return "zh-Hant" }
        if id.hasPrefix("pt-BR") || id == "pt" { return id.hasPrefix("pt-BR") || id == "pt-BR" ? "pt-BR" : (id.hasPrefix("pt") ? "pt-BR" : id) }
        if id.hasPrefix("pt") { return "pt-BR" }
        let primary = String(id.split(separator: "-").first ?? Substring(id))
        let known = ["en", "ja", "ko", "es", "fr", "de"]
        if known.contains(primary) { return primary }
        if id.hasPrefix("en") { return "en" }
        return id
    }

    private static func bestCatalogMatch(for preferred: String) -> String {
        let n = normalizeCatalogID(preferred)
        let known = Set(["en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR"])
        if known.contains(n) { return n }
        return "en"
    }

    private static func loadCatalog() -> [String: [String: String]] {
        var candidates: [URL] = []
        if let u = Bundle.module.url(forResource: "LocalizationCatalog", withExtension: "json", subdirectory: "Localization") {
            candidates.append(u)
        }
        if let u = Bundle.module.url(forResource: "LocalizationCatalog", withExtension: "json") {
            candidates.append(u)
        }
        if let u = Bundle.main.url(forResource: "LocalizationCatalog", withExtension: "json", subdirectory: "Localization") {
            candidates.append(u)
        }
        if let u = Bundle.main.url(forResource: "LocalizationCatalog", withExtension: "json") {
            candidates.append(u)
        }
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(
                exeDir.appendingPathComponent("AIStorageManager_AppServices.bundle")
                    .appendingPathComponent("LocalizationCatalog.json")
            )
            candidates.append(
                exeDir.appendingPathComponent("AIStorageManager_AppServices.bundle")
                    .appendingPathComponent("Localization")
                    .appendingPathComponent("LocalizationCatalog.json")
            )
        }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let strings = obj["strings"] as? [String: [String: String]],
               !strings.isEmpty {
                return strings
            }
        }
        return [:]
    }
}

public struct LocalizationLocaleCoverage: Codable, Sendable, Equatable {
    public var localeID: String
    public var totalKeys: Int
    public var translatedKeys: Int
    public var missingKeys: Int
    public var fallbackKeys: Int
    public var coveragePercent: Double
}
