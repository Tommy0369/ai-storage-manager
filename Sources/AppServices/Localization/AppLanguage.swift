import Foundation

/// P5.3 — presentation locale preference. Never influences Safety.
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case system = "system"
    case english = "en"
    case japanese = "ja"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portugueseBrazil = "pt-BR"

    public var id: String { rawValue }

    /// BCP-47 locale identifier used for catalog lookup / formatting.
    public var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .japanese: return "ja"
        case .chineseSimplified: return "zh-Hans"
        case .chineseTraditional: return "zh-Hant"
        case .korean: return "ko"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .portugueseBrazil: return "pt-BR"
        }
    }

    /// Native language name for the Settings picker (not country flags).
    public var displayNameNative: String {
        switch self {
        case .system: return "System Default" // localized at call site via settings.language.system
        case .english: return "English"
        case .japanese: return "日本語"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .korean: return "한국어"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .portugueseBrazil: return "Português (Brasil)"
        }
    }

    public var pickerLabel: String {
        switch self {
        case .system: return L10n.t("settings.language.system")
        default: return displayNameNative
        }
    }

    public static let shippingLocales: [AppLanguage] = [
        .english, .japanese, .chineseSimplified, .chineseTraditional,
        .korean, .spanish, .french, .german, .portugueseBrazil,
    ]

    public static func parse(_ raw: String?) -> AppLanguage {
        guard let raw, let value = AppLanguage(rawValue: raw) else { return .system }
        return value
    }
}
