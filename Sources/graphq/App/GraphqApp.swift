import AppKit
import SketchRender
import SwiftUI

@main
struct GraphqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { SketchDocument() }) { file in
            ContentView(document: file.document)
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands { SketchCommands() }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundledFonts()
        AppearanceController.apply()
        // When launched as a bare executable (`swift run`) make sure we behave like a GUI app.
        if Bundle.main.bundleIdentifier == nil {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

enum AppearanceController {
    @MainActor
    static func apply() {
        let raw = UserDefaults.standard.string(forKey: Preferences.appearanceKey) ?? "system"
        switch AppearancePreference(rawValue: raw) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Focused editor

struct FocusedEditorKey: FocusedValueKey {
    typealias Value = Editor
}

extension FocusedValues {
    var editor: Editor? {
        get { self[FocusedEditorKey.self] }
        set { self[FocusedEditorKey.self] = newValue }
    }
}
