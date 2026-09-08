import SwiftUI
import AppServices

enum CategoryMapColors {
    static func color(for category: ProductStorageCategory) -> Color {
        switch category {
        case .developer: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .aiTools: return Color(red: 0.55, green: 0.35, blue: 0.90)
        case .macOSSystem: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .personalFiles: return Color(red: 0.30, green: 0.70, blue: 0.45)
        case .cloud: return Color(red: 0.25, green: 0.65, blue: 0.85)
        case .backups: return Color(red: 0.85, green: 0.55, blue: 0.25)
        case .applications: return Color(red: 0.45, green: 0.45, blue: 0.85)
        case .generatedData: return Color(red: 0.70, green: 0.55, blue: 0.35)
        case .trash: return Color(red: 0.75, green: 0.35, blue: 0.35)
        case .otherUnknown: return Color(red: 0.60, green: 0.60, blue: 0.62)
        }
    }
}
