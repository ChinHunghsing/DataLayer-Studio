import AppKit
import OverlayCore
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeWindowView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.openWindow) private var openWindow
    @State private var windowBox = WeakWelcomeWindowBox()
    @State private var pendingSessionRevision: Int?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 600)
        .background(.regularMaterial)
        .background(WelcomeWindowReader { windowBox.window = $0 })
        .dropDestination(for: URL.self) { urls, _ in
            let revision = model.studioSessionRevision
            handleEntryResult(
                model.openExternalFiles(urls),
                opensEditor: shouldOpenEditor(for: urls),
                startingRevision: revision
            )
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.studioSessionRevision) { revision in
            guard revision > 0 else { return }
            self.pendingSessionRevision = nil
            closeWelcomeWindow()
        }
        .onOpenURL { url in
            let revision = model.studioSessionRevision
            handleEntryResult(
                model.openExternalFiles([url]),
                opensEditor: shouldOpenEditor(for: [url]),
                startingRevision: revision
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(localization.string("app.name"))
                    .font(.title2.weight(.semibold))
                Text(localization.string("welcome.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 0) {
            actionsColumn
                .frame(width: 260)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    recentProjectsSection
                    userTemplatesSection
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actionsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.string("welcome.start"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            actionButton("welcome.newProject", systemImage: "doc.badge.plus", prominent: true) {
                beginEntry { model.requestNewTimelineProject() }
            }
            actionButton("welcome.openProject", systemImage: "folder") {
                beginEntry { model.requestOpenTimelineProject() }
            }

            Divider()
                .padding(.vertical, 4)

            actionButton("startupPrompt.chooseVideo", systemImage: "film") {
                beginEntry { model.chooseMediaForNewTimelineProject(kind: .video) }
            }
            actionButton("startupPrompt.chooseActivity", systemImage: "figure.run") {
                beginEntry { model.chooseMediaForNewTimelineProject(kind: .activity) }
            }

            Text(localization.string("welcome.dropHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let error = model.studioEntryErrorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func actionButton(
        _ key: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if prominent {
                Button(action: action) {
                    actionLabel(key, systemImage: systemImage)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    actionLabel(key, systemImage: systemImage)
                }
                .buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.roundedRectangle)
    }

    private func actionLabel(_ key: String, systemImage: String) -> some View {
        Label(localization.string(key), systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("welcome.recentProjects")

            if model.recentTimelineProjects.isEmpty {
                emptyRow("welcome.noRecentProjects", systemImage: "clock")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.recentTimelineProjects) { project in
                        recentProjectRow(project)
                        if project.id != model.recentTimelineProjects.last?.id {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func recentProjectRow(_ project: RecentTimelineProject) -> some View {
        HStack(spacing: 10) {
            Image(systemName: project.isAvailable ? "doc.badge.clock" : "doc.badge.ellipsis")
                .foregroundStyle(project.isAvailable ? Color.accentColor : Color.orange)
                .frame(width: 20)

            Button {
                beginEntry { model.openExternalFiles([project.url]) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(project.url.deletingLastPathComponent().path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let lastOpenedAt = project.lastOpenedAt {
                            Text(lastOpenedAt, style: .relative)
                                .fixedSize()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!project.isAvailable)

            if project.isAvailable {
                Button {
                    model.removeRecentTimelineProject(project)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(localization.string("welcome.removeRecent"))
            } else {
                Button(localization.string("welcome.locate")) {
                    beginEntry { model.locateRecentTimelineProject(project) }
                }
                .controlSize(.small)
                Button {
                    model.removeRecentTimelineProject(project)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(localization.string("welcome.removeRecent"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var userTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("welcome.myTemplates")

            if model.layoutPresetsForDisplay.isEmpty {
                emptyRow("welcome.noTemplates", systemImage: "rectangle.3.group")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(model.layoutPresetsForDisplay) { preset in
                        Button {
                            beginEntry { model.requestNewTimelineProject(layoutPresetID: preset.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                LayoutPresetThumbnailView(layout: preset.layout)
                                    .frame(height: 88)
                                Text(preset.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(localization.string(key))
            .font(.headline)
    }

    private func emptyRow(_ key: String, systemImage: String) -> some View {
        Label(localization.string(key), systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 12)
            .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func beginEntry(_ request: () -> StudioEntryRequestResult) {
        let revision = model.studioSessionRevision
        let result = request()
        handleEntryResult(result, opensEditor: true, startingRevision: revision)
    }

    private func handleEntryResult(
        _ result: StudioEntryRequestResult,
        opensEditor: Bool,
        startingRevision: Int? = nil
    ) {
        guard opensEditor else { return }
        switch result {
        case .accepted:
            let revision = startingRevision ?? model.studioSessionRevision
            openWindow(id: "studio")
            if model.studioSessionRevision != revision {
                closeWelcomeWindow()
            } else {
                pendingSessionRevision = revision
            }
        case .cancelled, .failed:
            break
        }
    }

    private func shouldOpenEditor(for urls: [URL]) -> Bool {
        guard urls.count == 1, let url = urls.first else { return true }
        let kind = StudioExternalFileKind.classify(url)
        if kind == .legacyJSON,
           let data = try? Data(contentsOf: url) {
            return (try? JSONDecoder().decode(TimelineProject.self, from: data)) != nil
        }
        return kind != .layoutPreset
    }

    private func closeWelcomeWindow() {
        windowBox.window?.close()
    }
}

private final class WeakWelcomeWindowBox {
    weak var window: NSWindow?
}

private struct WelcomeWindowReader: NSViewRepresentable {
    var resolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else {
            DispatchQueue.main.async {
                if let window = nsView.window { resolve(window) }
            }
            return
        }
        resolve(window)
    }
}
