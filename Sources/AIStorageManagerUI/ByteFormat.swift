import AppServices

enum ByteFormat {
    static func label(_ bytes: Int64) -> String {
        LocaleFormatting.byteLabel(bytes)
    }

    static func label(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return LocaleFormatting.byteLabel(bytes)
    }
}
