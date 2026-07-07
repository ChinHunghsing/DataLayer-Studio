#if os(iOS)
import AVFoundation
import CoreTransferable
import OverlayCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 左栏：素材导入、对表、布局预设与导出。
struct TouchSourcesPanel: View {
    @ObservedObject var model: TouchStudioModel
    let subscriptionStore: MobileSubscriptionStore?
    let localizer: TouchLocalizer
    let showPaywall: () -> Void

    @State private var activeImporter: ImporterKind?
    @State private var isFileImporterPresented = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var isImportingPhotosVideo = false
    @State private var photosImportFailed = false
    @State private var presetName = ""

    private enum ImporterKind: Identifiable {
        case video
        case activity

        var id: Int {
            switch self {
            case .video: return 0
            case .activity: return 1
            }
        }

        var contentTypes: [UTType] {
            switch self {
            case .video:
                return [.movie, .video, .mpeg4Movie, .quickTimeMovie, .data, .item]
            case .activity:
                return [.data, .item]
            }
        }
    }

    var body: some View {
        Form {
            videoSection
            activitySection
            syncSection
            presetSection
            TouchExportSection(
                model: model,
                subscriptionStore: subscriptionStore,
                localizer: localizer,
                showPaywall: showPaywall
            )
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: activeImporter?.contentTypes ?? [.movie],
            allowsMultipleSelection: false
        ) { result in
            let kind = activeImporter
            activeImporter = nil
            isFileImporterPresented = false
            guard case let .success(urls) = result, let url = urls.first else { return }
            switch kind {
            case .video:
                model.setVideo(url, isSecurityScoped: true)
            case .activity:
                model.setActivityFile(url, isSecurityScoped: true)
            case nil:
                break
            }
        }
        .onChange(of: photosPickerItem) { _, item in
            guard let item else { return }
            importPhotosVideo(item)
        }
        .alert(localizer.string("sources.photosImportFailed"), isPresented: $photosImportFailed) {
            Button(localizer.string("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: - 视频

    private var videoSection: some View {
        Section(localizer.string("sources.video")) {
            if let metadata = model.metadata, let videoURL = model.videoURL {
                LabeledContent(localizer.string("sources.video")) {
                    Text(videoURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent(localizer.string("sources.resolution")) {
                    Text(verbatim: "\(String(Int(metadata.size.width.rounded())))×\(String(Int(metadata.size.height.rounded())))")
                }
                LabeledContent(localizer.string("sources.frameRate")) {
                    Text(String(format: "%.2f fps", metadata.framesPerSecond))
                }
                LabeledContent(localizer.string("sources.duration")) {
                    Text(TouchStudioModel.formatSeconds(metadata.duration))
                }
            } else if let failure = model.videoLoadFailure {
                Label(failure.detail, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button(localizer.string("sources.retry")) {
                    model.retryVideoLoad()
                }
            } else {
                Text(localizer.string("sources.videoEmptyHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isImportingPhotosVideo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(localizer.string("sources.importingPhotosVideo"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                activeImporter = .video
                isFileImporterPresented = true
            } label: {
                Label(localizer.string("sources.chooseVideo"), systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(model.isExporting || isImportingPhotosVideo)

            PhotosPicker(selection: $photosPickerItem, matching: .videos, photoLibrary: .shared()) {
                Label(localizer.string("sources.chooseFromPhotos"), systemImage: "photo.on.rectangle")
            }
            .disabled(model.isExporting || isImportingPhotosVideo)
        }
    }

    private func importPhotosVideo(_ item: PhotosPickerItem) {
        isImportingPhotosVideo = true
        Task { @MainActor in
            defer {
                isImportingPhotosVideo = false
                photosPickerItem = nil
            }
            do {
                guard let movie = try await item.loadTransferable(type: TouchImportedMovie.self) else {
                    photosImportFailed = true
                    return
                }
                model.setVideo(movie.url, isSecurityScoped: false)
                TouchImportedMovie.removeStaleImportedFiles(keeping: movie.url)
            } catch {
                photosImportFailed = true
            }
        }
    }

    // MARK: - 活动文件

    private var activitySection: some View {
        Section(localizer.string("sources.activity")) {
            if let series = model.series, let activityURL = model.activityURL {
                LabeledContent(localizer.string("sources.activity")) {
                    Text(activityURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent(localizer.string("sources.samples")) {
                    Text(verbatim: String(series.samples.count))
                }
                LabeledContent(localizer.string("sources.duration")) {
                    Text(TouchStudioModel.formatSeconds(series.duration))
                }
            } else if let failure = model.activityLoadFailure {
                Label(failure.detail, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button(localizer.string("sources.retry")) {
                    model.retryActivityLoad()
                }
            } else {
                Text(localizer.string("sources.activityEmptyHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                activeImporter = .activity
                isFileImporterPresented = true
            } label: {
                Label(localizer.string("sources.chooseActivity"), systemImage: "figure.outdoor.cycle")
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model.isExporting)
        }
    }

    // MARK: - 对表

    private var syncSection: some View {
        Section(localizer.string("sync.title")) {
            Picker(localizer.string("sync.title"), selection: $model.syncMode) {
                ForEach(TouchSyncMode.allCases) { mode in
                    Text(localizer.string("sync.mode.\(mode.rawValue)")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.syncMode) { _, _ in
                model.applySyncChange()
            }

            switch model.syncMode {
            case .offset:
                syncField(labelKey: "sync.offsetSeconds", value: $model.offsetSeconds)
            case .fitStart:
                syncField(labelKey: "sync.fitStartSeconds", value: $model.fitStartSeconds)
            case .syncPoint:
                syncField(labelKey: "sync.videoSeconds", value: $model.syncVideoSeconds)
                syncField(labelKey: "sync.fitSeconds", value: $model.syncFITSeconds)
            }

            Button {
                model.markSportStart()
            } label: {
                Label(localizer.string("sync.markSportStart"), systemImage: "flag.checkered")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(model.isExporting || model.previewDuration <= 0)
        }
    }

    private func syncField(labelKey: String, value: Binding<Double>) -> some View {
        LabeledContent(localizer.string(labelKey)) {
            TextField(
                localizer.string(labelKey),
                value: Binding(
                    get: { value.wrappedValue },
                    set: {
                        value.wrappedValue = $0
                        model.applySyncChange()
                    }
                ),
                format: .number.grouping(.never)
            )
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 120)
        }
    }

    // MARK: - 预设

    private var presetSection: some View {
        Section {
            HStack {
                TextField(localizer.string("presets.namePlaceholder"), text: $presetName)
                Button(localizer.string("presets.save")) {
                    if model.saveLayoutPreset(named: presetName) {
                        presetName = ""
                    }
                }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.layoutPresets.isEmpty {
                Text(localizer.string("presets.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.layoutPresetsForDisplay) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            if preset.id == model.defaultLayoutPresetID {
                                Text(localizer.string("presets.default"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Menu {
                            Button(localizer.string("presets.apply")) {
                                model.applyLayoutPreset(id: preset.id)
                            }
                            Button(localizer.string("presets.setDefault")) {
                                model.setDefaultLayoutPreset(id: preset.id)
                            }
                            Button(localizer.string("presets.delete"), role: .destructive) {
                                model.deleteLayoutPreset(id: preset.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(model.isExporting)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.applyLayoutPreset(id: preset.id)
                    }
                }
            }
        } header: {
            Text(localizer.string("presets.title"))
        } footer: {
            Text(presetSyncStatusText)
                .font(.caption)
        }
    }

    private var presetSyncStatusText: String {
        switch model.presetSyncStatus {
        case .localOnly:
            return localizer.string("presets.sync.localOnly")
        case .ready:
            return localizer.string("presets.sync.ready")
        case .uploadRequested:
            return localizer.string("presets.sync.uploadRequested")
        case .receivedUpdate:
            return localizer.string("presets.sync.receivedUpdate")
        }
    }
}

/// 照片图库视频经 FileRepresentation 拷贝到临时目录后导入。
struct TouchImportedMovie: Transferable {
    static let importedFilePrefix = "photos-import-"

    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(importedFilePrefix)\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return TouchImportedMovie(url: destination)
        }
    }

    /// 导入的视频可达数 GB，替换素材或跨会话残留会持续占用存储，必须主动清理。
    static func removeStaleImportedFiles(keeping keptURL: URL? = nil) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(importedFilePrefix) {
            if let keptURL, entry.standardizedFileURL == keptURL.standardizedFileURL {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }
}
#endif
