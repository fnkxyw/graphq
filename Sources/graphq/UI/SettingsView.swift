import SketchCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.appearanceKey) private var appearance = AppearancePreference.system.rawValue
    @AppStorage(Preferences.gridByDefaultKey) private var gridByDefault = false
    @AppStorage(Preferences.snapToObjectsKey) private var snapToObjects = true
    @AppStorage(Preferences.sloppinessKey) private var sloppiness = Sloppiness.artist.rawValue
    @AppStorage(Preferences.fontKey) private var font = FontFamily.hand.rawValue
    @AppStorage(Preferences.showHintsKey) private var showHints = true

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { AppearanceController.apply() }
                Toggle("Show hints on empty canvas", isOn: $showHints)
            }
            Section("New drawings") {
                Toggle("Show grid", isOn: $gridByDefault)
                Toggle("Snap to objects", isOn: $snapToObjects)
                Picker("Sloppiness", selection: $sloppiness) {
                    ForEach(Sloppiness.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Font", selection: $font) {
                    ForEach(FontFamily.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
