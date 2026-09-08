import Foundation

/// Locale-aware presentation formatting. Never mutates byte/Safety truth.
public enum LocaleFormatting {
    public static func byteLabel(_ bytes: Int64, language: AppLanguage = L10n.currentLanguage()) -> String {
        let locale = L10n.resolvedLocale(for: language)
        return bytes.formatted(
            .byteCount(style: .file)
            .locale(locale)
        )
    }

    public static func number(_ value: Double, language: AppLanguage = L10n.currentLanguage()) -> String {
        value.formatted(.number.locale(L10n.resolvedLocale(for: language)))
    }

    public static func integer(_ value: Int, language: AppLanguage = L10n.currentLanguage()) -> String {
        value.formatted(.number.locale(L10n.resolvedLocale(for: language)))
    }

    public static func date(_ date: Date, language: AppLanguage = L10n.currentLanguage()) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(L10n.resolvedLocale(for: language))
        )
    }
}
