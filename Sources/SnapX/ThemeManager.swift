import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    static let themeChangedNotification = Notification.Name("ThemeManager.themeChanged")

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.themeKey)
            applyTheme()
            NotificationCenter.default.post(name: Self.themeChangedNotification, object: nil)
        }
    }

    private static let themeKey = "app_theme"

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? "system"
        currentTheme = AppTheme(rawValue: savedTheme) ?? .system
        applyTheme()
    }

    private func applyTheme() {
        guard let appearance = currentTheme.nsAppearance else { return }

        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
            window.contentView?.needsDisplay = true
        }
    }

    func applyTheme(to window: NSWindow?) {
        guard let window = window else { return }

        if let appearance = currentTheme.nsAppearance {
            window.appearance = appearance
            window.contentView?.appearance = appearance
        } else {
            window.appearance = nil
            window.contentView?.appearance = nil
        }
        window.contentView?.needsDisplay = true
    }
}
