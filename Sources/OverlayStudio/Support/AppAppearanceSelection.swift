import SwiftUI

enum AppAppearanceSelection: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "run.libo.overlay-studio.appearance.v1"

    var id: String { rawValue }

    var localizedKey: String {
        "settings.appearance.\(rawValue)"
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func selection(from rawValue: String) -> AppAppearanceSelection {
        AppAppearanceSelection(rawValue: rawValue) ?? .system
    }
}
