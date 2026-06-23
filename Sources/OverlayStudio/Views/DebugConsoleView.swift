import AppKit
import SwiftUI

struct DebugConsoleView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory = "all"
    @State private var searchText = ""

    private var filteredEntries: [DebugLogEntry] {
        model.debugLogEntries
            .filter { entry in
                selectedCategory == "all" || entry.category.rawValue == selectedCategory
            }
            .filter { entry in
                searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
            }
            .reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if filteredEntries.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .frame(width: 760, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localization.string("debug.consoleTitle"), systemImage: "ladybug")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button(localization.string("debug.copyVisible")) {
                    copy(filteredEntries)
                }
                .disabled(filteredEntries.isEmpty)

                Button(role: .destructive) {
                    model.clearDebugLog()
                } label: {
                    Text(localization.string("debug.clear"))
                }
                .disabled(model.debugLogEntries.isEmpty)

                Button(localization.string("common.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 10) {
                Picker(localization.string("debug.category"), selection: $selectedCategory) {
                    Text(localization.string("debug.category.all")).tag("all")
                    ForEach(DebugLogCategory.allCases) { category in
                        Text(localization.string(category.titleKey)).tag(category.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                TextField(localization.string("debug.search"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Text(String(format: localization.string("debug.visibleCount"), filteredEntries.count, model.debugLogEntries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(localization.string("debug.empty"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logList: some View {
        List(filteredEntries) { entry in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                    Text(localization.string(entry.category.titleKey))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 5)
        }
        .listStyle(.inset)
    }

    private func copy(_ entries: [DebugLogEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugLogText(entries), forType: .string)
    }

    private func debugLogText(_ entries: [DebugLogEntry]) -> String {
        entries.map { entry in
            "\(entry.date.formatted(date: .numeric, time: .standard)) [\(entry.category.rawValue)] \(entry.message)"
        }
        .joined(separator: "\n")
    }
}
