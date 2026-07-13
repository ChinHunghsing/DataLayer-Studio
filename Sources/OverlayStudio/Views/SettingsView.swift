import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @AppStorage(AppAppearanceSelection.defaultsKey) private var appearanceRawValue = AppAppearanceSelection.system.rawValue

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

                Section {
                    Picker(localization.string("settings.appearance.picker"), selection: appearanceSelection) {
                        ForEach(AppAppearanceSelection.allCases) { selection in
                            Text(localization.string(selection.localizedKey)).tag(selection)
                        }
                    }
                    Text(localization.string("settings.appearance.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(localization.string("settings.appearance.title"))
                }

                Section {
                    Stepper(value: safeAreaInsetSelection, in: 0...20, step: 1) {
                        HStack {
                            Text(localization.string("settings.canvas.safeAreaInset"))
                            Spacer()
                            Text("\(Int(model.canvasSafeAreaInsetPercent.rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(localization.string("settings.canvas.safeAreaInset.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(localization.string("settings.canvas.title"))
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(localization.string("settings.general"), systemImage: "gearshape")
            }
        }
        .frame(width: 460, height: 320)
        .scenePadding()
    }

    private var appearanceSelection: Binding<AppAppearanceSelection> {
        Binding {
            AppAppearanceSelection.selection(from: appearanceRawValue)
        } set: { selection in
            appearanceRawValue = selection.rawValue
        }
    }

    private var safeAreaInsetSelection: Binding<Double> {
        Binding {
            model.canvasSafeAreaInsetPercent
        } set: { value in
            model.setCanvasSafeAreaInsetPercent(value)
        }
    }
}
