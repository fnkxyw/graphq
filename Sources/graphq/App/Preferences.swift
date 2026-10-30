import Foundation
import SketchCore
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// UserDefaults keys used by Settings (via @AppStorage) and read at editor creation.
enum Preferences {
    static let appearanceKey = "appearance"
    static let gridByDefaultKey = "gridByDefault"
    static let snapToObjectsKey = "snapToObjects"
    static let sloppinessKey = "defaultSloppiness"
    static let fontKey = "defaultFont"
    static let showHintsKey = "showEmptyStateHint"

    private static var defaults: UserDefaults { .standard }

    static var gridByDefault: Bool { defaults.bool(forKey: gridByDefaultKey) }

    static var snapToObjectsDefault: Bool {
        defaults.object(forKey: snapToObjectsKey) as? Bool ?? true
    }

    static var defaultSloppiness: Sloppiness {
        Sloppiness(rawValue: defaults.object(forKey: sloppinessKey) as? Double ?? 1) ?? .artist
    }

    static var defaultFontFamily: FontFamily {
        FontFamily(rawValue: defaults.string(forKey: fontKey) ?? "hand") ?? .hand
    }

    static var showHints: Bool { defaults.object(forKey: showHintsKey) as? Bool ?? true }
}
