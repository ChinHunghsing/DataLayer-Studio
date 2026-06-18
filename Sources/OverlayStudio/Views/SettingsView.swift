import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker(localization.string("settings.language.picker"), selection: $localization.selection) {
                        ForEach(AppLanguageSelection.allCases) { selection in
                            Text(selection.nativeName).tag(selection)
                        }
                    }
                    Text(localization.string("settings.language.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(localization.string("settings.language.title"))
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(localization.string("settings.general"), systemImage: "gearshape")
            }
        }
        .frame(width: 460, height: 240)
        .scenePadding()
    }
}
