import Foundation
import OverlayCore
import SwiftUI

enum AppLanguageSelection: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case traditionalChinese
    case english
    case japanese

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system:
            return AppLocalizer.currentString("language.system")
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        }
    }
}

enum AppResolvedLanguage: String, CaseIterable {
    case simplifiedChinese
    case traditionalChinese
    case english
    case japanese

    var localeIdentifier: String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .english:
            return "en"
        case .japanese:
            return "ja"
        }
    }
}

@MainActor
final class LocalizationStore: ObservableObject {
    @Published var selection: AppLanguageSelection {
        didSet {
            defaults.set(selection.rawValue, forKey: AppLocalizer.selectionDefaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selection = AppLocalizer.storedSelection(defaults: defaults)
    }

    var resolvedLanguage: AppResolvedLanguage {
        AppLocalizer.resolvedLanguage(for: selection)
    }

    var locale: Locale {
        Locale(identifier: resolvedLanguage.localeIdentifier)
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalizer.string(key, language: resolvedLanguage, arguments: arguments)
    }
}

enum AppLocalizer {
    static let selectionDefaultsKey = "run.libo.overlay-studio.language.v1"

    static func storedSelection(
        defaults: UserDefaults = .standard,
        appDomains: [String] = DataLayerStudioDefaults.appDomains
    ) -> AppLanguageSelection {
        if let selection = selection(from: defaults.string(forKey: selectionDefaultsKey)) {
            return selection
        }

        for domain in appDomains {
            let rawValue = defaults.persistentDomain(forName: domain)?[selectionDefaultsKey] as? String
            if let selection = selection(from: rawValue) {
                return selection
            }
        }

        return .system
    }

    static func resolvedLanguage(for selection: AppLanguageSelection) -> AppResolvedLanguage {
        switch selection {
        case .system:
            return resolvedLanguage(forPreferredLanguages: Locale.preferredLanguages)
        case .simplifiedChinese:
            return .simplifiedChinese
        case .traditionalChinese:
            return .traditionalChinese
        case .english:
            return .english
        case .japanese:
            return .japanese
        }
    }

    static func resolvedLanguage(forPreferredLanguages preferredLanguages: [String]) -> AppResolvedLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if normalized.hasPrefix("zh-hant")
                || normalized.hasPrefix("zh-tw")
                || normalized.hasPrefix("zh-hk")
                || normalized.hasPrefix("zh-mo") {
                return .traditionalChinese
            }
            if normalized.hasPrefix("zh-hans")
                || normalized.hasPrefix("zh-cn")
                || normalized.hasPrefix("zh-sg")
                || normalized.hasPrefix("zh-my")
                || normalized == "zh" {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("ja") {
                return .japanese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }

    private static func selection(from rawValue: String?) -> AppLanguageSelection? {
        guard let rawValue else { return nil }
        return AppLanguageSelection(rawValue: rawValue)
    }

    static func currentString(_ key: String, _ arguments: CVarArg...) -> String {
        currentString(key, arguments: arguments)
    }

    static func currentString(_ key: String, arguments: [CVarArg]) -> String {
        string(key, language: resolvedLanguage(for: storedSelection()), arguments: arguments)
    }

    static func string(_ key: String, language: AppResolvedLanguage, arguments: [CVarArg] = []) -> String {
        let table = translations[language] ?? translations[.english] ?? [:]
        let format = table[key] ?? translations[.english]?[key] ?? key
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language.localeIdentifier),
            arguments: arguments
        )
    }

    static func missingTranslationKeys(for language: AppResolvedLanguage) -> [String] {
        let baseKeys = Set(english.keys)
        let translatedKeys = Set(translations[language].map { Array($0.keys) } ?? [])
        return Array(baseKeys.subtracting(translatedKeys)).sorted()
    }

    private static let translations: [AppResolvedLanguage: [String: String]] = [
        .english: english,
        .simplifiedChinese: simplifiedChinese,
        .traditionalChinese: traditionalChinese,
        .japanese: japanese
    ]

    private static let english: [String: String] = [
        "app.name": "DataLayer Studio",
        "language.system": "Follow System",
        "settings.general": "General",
        "settings.language.title": "Language",
        "settings.language.picker": "App language",
        "settings.language.description": "Default follows the system language. Manual selection applies immediately.",

        "menu.openVideo": "Open Video...",
        "menu.openFit": "Open FIT...",
        "menu.exportOverlay": "Export Overlay...",
        "menu.cancelExport": "Cancel Export",
        "menu.arrange": "Arrange",
        "menu.bringForward": "Bring Forward",
        "menu.sendBackward": "Send Backward",
        "menu.preview": "Preview",
        "menu.refreshPreview": "Refresh Preview",
        "menu.pausePreview": "Pause Preview",
        "menu.playPreview": "Play Preview",
        "menu.setSportStart": "Set Sport Start",
        "menu.zoomIn": "Zoom In",
        "menu.zoomOut": "Zoom Out",
        "menu.resetZoom": "Reset Zoom",
        "menu.exitPreviewFullscreen": "Exit Preview Full Screen",
        "menu.enterPreviewFullscreen": "Enter Preview Full Screen",

        "toolbar.refreshPreview": "Refresh Preview",
        "toolbar.sportStart": "Sport Start",
        "toolbar.output": "Output",
        "toolbar.cancelExport": "Cancel Export",
        "toolbar.export": "Export",
        "help.cancelExport": "Cancel export",
        "help.exportTransparentOverlay": "Export transparent overlay video",

        "sidebar.workflowTabs": "Workflow steps",
        "sidebar.source.title": "Source",
        "sidebar.source.subtitle": "Video and FIT activity data",
        "sidebar.video.title": "Video",
        "sidebar.video.placeholder": "Choose source video",
        "sidebar.fit.title": "FIT",
        "sidebar.fit.placeholder": "Choose activity.fit",
        "sidebar.sync.title": "Sync",
        "sidebar.sync.subtitle": "Match video time with activity time",
        "sidebar.mode": "Mode",
        "sidebar.sportStart": "Sport Start",
        "sidebar.offset": "Offset",
        "sidebar.offset.description": "Positive means video starts before FIT. Negative means video starts mid-activity.",
        "sidebar.videoZeroFit": "Video 0 = FIT",
        "sidebar.videoPoint": "Video point",
        "sidebar.fitPoint": "FIT point",
        "sidebar.sync.mode": "How to sync",
        "sidebar.sync.currentFrame": "Current preview",
        "sidebar.sync.currentMapping": "Video %@ = Activity %@",
        "sidebar.sync.beforeActivity": "%@ before start",
        "sidebar.sync.setCurrentAsStart": "Current frame is sport start",
        "sidebar.sync.setCurrentAsStartHelp": "Scrub to the frame where you started the watch, then click this. It sets that video time to activity 00:00.",
        "sidebar.sync.videoTime": "Video",
        "sidebar.sync.activityTime": "Activity",
        "sidebar.sync.matchHelp": "Use this when you can identify the same moment in the video and the activity.",
        "sidebar.sync.activityAtVideoStart": "At 00:00",
        "sidebar.sync.whenToUse": "When to use",
        "sidebar.sync.videoStartHelp": "Use this when recording starts after the activity has already begun. Enter the activity elapsed time at video 00:00.",
        "sidebar.sync.manualOffset": "Offset",
        "sidebar.sync.time.sign": "Sign",
        "sidebar.sync.time.hours": "h",
        "sidebar.sync.time.minutes": "m",
        "sidebar.sync.time.seconds": "s",
        "sidebar.sync.offsetResult": "Result",
        "sidebar.sync.offsetAligned": "Video 00:00 and activity 00:00 are aligned.",
        "sidebar.sync.offsetVideoBeforeFit": "Activity starts %@ after the video begins.",
        "sidebar.sync.offsetVideoAfterFit": "Video begins %@ after the activity starts.",
        "sidebar.sync.manualOffsetHelp": "Advanced mode. Positive values mean the activity starts later in the video; negative values mean the video begins mid-activity.",
        "sidebar.canvas.title": "Canvas",
        "sidebar.canvas.subtitle": "Preview grid and reusable gauge layouts",
        "sidebar.videoSettings": "Video",
        "sidebar.resolution": "Resolution",
        "sidebar.sourceResolutionPreset": "Source %d×%d",
        "sidebar.custom": "Custom",
        "sidebar.width": "Width",
        "sidebar.height": "Height",
        "sidebar.frameRate": "Frame rate",
        "sidebar.sourceFrameRatePreset": "Source %@ fps",
        "sidebar.fps": "FPS",
        "sidebar.duration": "Duration",
        "sidebar.bitrate": "Bitrate",
        "sidebar.distanceUnit": "Distance unit",
        "sidebar.codec": "Codec",
        "sidebar.destination": "Destination",
        "sidebar.saveAs": "Save as",
        "sidebar.askWhenExporting": "Ask when exporting",
        "sidebar.grid": "Grid",
        "sidebar.showGrid": "Show grid",
        "sidebar.snapWhileDragging": "Snap while dragging",
        "sidebar.columns": "Columns",
        "sidebar.rows": "Rows",
        "sidebar.presets": "Presets",
        "sidebar.presetName": "Preset name",
        "sidebar.save": "Save",
        "sidebar.saveCurrentLayout": "Save current layout",
        "sidebar.import": "Import",
        "sidebar.export": "Export",
        "sidebar.noSavedPresets": "No saved presets.",
        "sidebar.export.title": "Export",
        "sidebar.export.subtitle": "Transparent overlay render settings",
        "sidebar.render": "Render",
        "sidebar.exportingOverlay": "Exporting overlay",
        "sidebar.exportProgress": "Export progress",
        "sidebar.exportDisabled": "Export disabled",
        "sidebar.exportOverlay": "Export Overlay",

        "preset.default": "Default",
        "preset.gaugeCount": "%d gauges",
        "preset.apply": "Apply",
        "preset.applyHelp": "Apply preset",
        "preset.setDefault": "Set default",
        "preset.setDefaultHelp": "Set as default",
        "preset.delete": "Delete",
        "preset.deleteHelp": "Delete preset",
        "preset.deleteDialogTitle": "Delete layout preset?",
        "preset.deleteNamed": "Delete %@",
        "preset.deleteDialogMessage": "This removes the saved preset. The current canvas layout is not changed.",
        "common.cancel": "Cancel",

        "inspector.noSelection.title": "No element selected",
        "inspector.noSelection.subtitle": "Click a gauge in preview",
        "inspector.noSelection.message": "Click a visible gauge in the preview canvas, or add a new element.",
        "inspector.addElement": "Add element",
        "inspector.duplicate": "Duplicate selected element",
        "inspector.sendBackward": "Send selected element backward",
        "inspector.bringForward": "Bring selected element forward",
        "inspector.delete": "Delete selected element",
        "inspector.visible": "Visible",
        "inspector.size": "Size",
        "inspector.length": "Length",
        "inspector.label": "Label",
        "inspector.labelText": "Label text",
        "inspector.endLabel": "End label",
        "inspector.clockAndDate": "Clock & date",
        "inspector.unit": "Unit",
        "inspector.unitText": "Unit text",
        "inspector.icon": "Icon",
        "inspector.iconText": "Icon text",
        "inspector.panel": "Panel",
        "inspector.panelBorder": "Panel border",
        "inspector.panelOpacity": "Panel opacity",
        "inspector.gaugeWidth": "Gauge width",
        "inspector.lineWidth": "Line width",
        "inspector.trackColor": "Track color",
        "inspector.progressColor": "Progress color",
        "inspector.sidePadding": "Side padding",
        "inspector.knobSize": "Knob size",
        "inspector.valueMargin": "Value margin",
        "inspector.tickMarks": "Tick marks",
        "inspector.tickCount": "Tick count",
        "inspector.value": "Value",
        "inspector.decimals": "Decimals: %d",
        "inspector.gaugeTicks": "Gauge ticks",
        "inspector.gaugeMin": "Gauge min",
        "inspector.gaugeMax": "Gauge max",
        "inspector.layout": "Layout",
        "inspector.appearance": "Appearance",
        "inspector.content": "Content",
        "inspector.typography": "Typography",
        "inspector.data": "Data",
        "inspector.font": "Font",
        "inspector.color": "Color",
        "inspector.fontSize": "Font size",

        "preview.time": "Preview %@",
        "preview.sportStartAt": "Sport Start: %@",
        "preview.warning": "Preview warning",
        "preview.play": "Play",
        "preview.pause": "Pause",
        "preview.zoomOut": "Zoom Out",
        "preview.zoomOutHelp": "Zoom out",
        "preview.zoomIn": "Zoom In",
        "preview.zoomInHelp": "Zoom in",
        "preview.fit": "Fit",
        "preview.fitHelp": "Fit to preview",
        "preview.exitFullscreen": "Exit Full Screen",
        "preview.fullscreen": "Full Screen",
        "preview.exitFullscreenHelp": "Exit full screen",
        "preview.fullscreenHelp": "Full screen",
        "preview.placeholder.title": "Choose a video and FIT file",
        "preview.placeholder.subtitle": "The overlay can be dragged and resized after preview loads.",
        "preview.selected": "Selected",
        "preview.notSelected": "Not selected",
        "preview.elementHint": "Click to select. Drag to move.",

        "sync.offset": "Manual",
        "sync.fitStart": "Video start",
        "sync.syncPoint": "Match point",

        "component.speed": "Speed",
        "component.pace": "Pace",
        "component.heartRate": "Heart rate",
        "component.cadence": "Cadence",
        "component.distanceValue": "Distance value",
        "component.gpsRoute": "GPS route",
        "component.distance": "Distance",
        "component.timeDate": "Time & Date",

        "codec.hevcAlpha": "HEVC/H.265 with alpha",
        "codec.proRes4444": "Apple ProRes 4444",
        "unit.meters": "Meters (m)",
        "unit.kilometers": "Kilometers (km)",

        "status.chooseVideoAndFit": "Choose a video and a FIT file.",
        "status.chooseSourceVideo": "Choose a source video.",
        "status.chooseFitFile": "Choose a FIT file.",
        "status.outputWidthRange": "Set output width between 2 and 16,384 px.",
        "status.outputWidthEven": "Set output width to an even pixel value.",
        "status.outputHeightRange": "Set output height between 2 and 16,384 px.",
        "status.outputHeightEven": "Set output height to an even pixel value.",
        "status.frameRateRange": "Set frame rate between 1 and 240 fps.",
        "status.durationRange": "Set duration between 0.1 s and 24 h.",
        "status.bitrateRange": "Set bitrate between 1 and 1,000,000 kbps.",
        "status.bitrateTooLarge": "Bitrate is too large for this Mac.",
        "status.exportCancelled": "Export cancelled.",
        "status.presetNameRequired": "Preset name is required.",
        "status.updatedPreset": "Updated layout preset: %@",
        "status.savedPreset": "Saved layout preset: %@",
        "status.appliedPreset": "Applied layout preset: %@",
        "status.defaultPreset": "Default layout preset: %@",
        "status.deletedPreset": "Deleted layout preset: %@",
        "status.noPresetsToExport": "No layout presets to export.",
        "status.exportedPresets": "Exported %d layout presets.",
        "status.presetExportError": "Preset export error: %@",
        "status.noPresetsImported": "No layout presets imported.",
        "status.importedPresets": "Imported %d layout presets.",
        "status.presetImportError": "Preset import error: %@",
        "status.loadingVideo": "Loading video: %@",
        "status.loadedVideo": "Loaded video: %@",
        "status.videoError": "Video error: %@",
        "status.sportStartSet": "Sport start set at video %@; activity starts at 00:00.",
        "status.loadingFit": "Loading FIT: %@",
        "status.loadedFit": "Loaded FIT: %@",
        "status.fitError": "FIT error: %@",
        "status.previewVideoFailed": "Video frame preview failed",
        "status.previewOverlayFailed": "Overlay preview failed",
        "status.checkOutputSettings": "Check output settings: width/height, fps, and bitrate must be in range.",
        "status.chooseOutputFile": "Choose an output file to export.",
        "status.chooseFitBeforeExport": "Choose a FIT file before exporting.",
        "status.exporting": "Exporting...",
        "status.wroteFile": "Wrote %@",
        "status.exportError": "Export error: %@",
        "status.cancellingExport": "Cancelling export...",

        "panel.chooseSourceVideo": "Choose source video",
        "panel.chooseFitActivity": "Choose FIT activity",
        "panel.saveOverlayVideo": "Save transparent overlay video",
        "panel.exportLayoutPresets": "Export layout presets",
        "panel.importLayoutPresets": "Import layout presets"
    ]

    private static let simplifiedChinese: [String: String] = [
        "app.name": "DataLayer Studio",
        "language.system": "跟随系统",
        "settings.general": "通用",
        "settings.language.title": "语言",
        "settings.language.picker": "应用语言",
        "settings.language.description": "默认跟随系统语言。手动选择后会立即生效。",

        "menu.openVideo": "打开视频...",
        "menu.openFit": "打开 FIT...",
        "menu.exportOverlay": "导出浮层...",
        "menu.cancelExport": "取消导出",
        "menu.arrange": "排列",
        "menu.bringForward": "上移一层",
        "menu.sendBackward": "下移一层",
        "menu.preview": "预览",
        "menu.refreshPreview": "刷新预览",
        "menu.pausePreview": "暂停预览",
        "menu.playPreview": "播放预览",
        "menu.setSportStart": "设置运动开始",
        "menu.zoomIn": "放大",
        "menu.zoomOut": "缩小",
        "menu.resetZoom": "重置缩放",
        "menu.exitPreviewFullscreen": "退出预览全屏",
        "menu.enterPreviewFullscreen": "进入预览全屏",

        "toolbar.refreshPreview": "刷新预览",
        "toolbar.sportStart": "运动开始",
        "toolbar.output": "输出",
        "toolbar.cancelExport": "取消导出",
        "toolbar.export": "导出",
        "help.cancelExport": "取消导出",
        "help.exportTransparentOverlay": "导出透明浮层视频",

        "sidebar.workflowTabs": "工作流步骤",
        "sidebar.source.title": "素材",
        "sidebar.source.subtitle": "视频和 FIT 运动数据",
        "sidebar.video.title": "视频",
        "sidebar.video.placeholder": "选择源视频",
        "sidebar.fit.title": "FIT",
        "sidebar.fit.placeholder": "选择 activity.fit",
        "sidebar.sync.title": "同步",
        "sidebar.sync.subtitle": "匹配视频时间和运动时间",
        "sidebar.mode": "模式",
        "sidebar.sportStart": "运动开始",
        "sidebar.offset": "偏移",
        "sidebar.offset.description": "正数表示视频早于 FIT 开始。负数表示视频从运动中途开始。",
        "sidebar.videoZeroFit": "视频 0 = FIT",
        "sidebar.videoPoint": "视频点",
        "sidebar.fitPoint": "FIT 点",
        "sidebar.sync.mode": "同步方式",
        "sidebar.sync.currentFrame": "当前预览",
        "sidebar.sync.currentMapping": "视频 %@ = 运动 %@",
        "sidebar.sync.beforeActivity": "运动开始前 %@",
        "sidebar.sync.setCurrentAsStart": "当前画面就是运动开始",
        "sidebar.sync.setCurrentAsStartHelp": "先把播放头拖到开表那一帧，再点这里。它会把这个视频时间设为运动 00:00。",
        "sidebar.sync.videoTime": "视频",
        "sidebar.sync.activityTime": "运动",
        "sidebar.sync.matchHelp": "当你能在视频和运动数据里找到同一个瞬间时，用这个方式最直觉。",
        "sidebar.sync.activityAtVideoStart": "00:00 时",
        "sidebar.sync.whenToUse": "适用场景",
        "sidebar.sync.videoStartHelp": "如果录像开始时运动已经进行了一段时间，输入视频 00:00 对应的运动用时。",
        "sidebar.sync.manualOffset": "偏移",
        "sidebar.sync.time.sign": "正负",
        "sidebar.sync.time.hours": "时",
        "sidebar.sync.time.minutes": "分",
        "sidebar.sync.time.seconds": "秒",
        "sidebar.sync.offsetResult": "结果",
        "sidebar.sync.offsetAligned": "视频 00:00 和运动 00:00 已对齐。",
        "sidebar.sync.offsetVideoBeforeFit": "运动在视频开始 %@ 后开始。",
        "sidebar.sync.offsetVideoAfterFit": "视频在运动开始 %@ 后开始。",
        "sidebar.sync.manualOffsetHelp": "高级模式。正数表示运动在视频中稍后开始；负数表示视频从运动中途开始。",
        "sidebar.canvas.title": "画布",
        "sidebar.canvas.subtitle": "预览网格和可复用浮层布局",
        "sidebar.videoSettings": "视频",
        "sidebar.resolution": "分辨率",
        "sidebar.sourceResolutionPreset": "源视频 %d×%d",
        "sidebar.custom": "自定义",
        "sidebar.width": "宽度",
        "sidebar.height": "高度",
        "sidebar.frameRate": "帧率",
        "sidebar.sourceFrameRatePreset": "源视频 %@ fps",
        "sidebar.fps": "帧率",
        "sidebar.duration": "时长",
        "sidebar.bitrate": "码率",
        "sidebar.distanceUnit": "距离单位",
        "sidebar.codec": "编码",
        "sidebar.destination": "目标",
        "sidebar.saveAs": "另存为",
        "sidebar.askWhenExporting": "导出时询问",
        "sidebar.grid": "网格",
        "sidebar.showGrid": "显示网格",
        "sidebar.snapWhileDragging": "拖动时吸附",
        "sidebar.columns": "列数",
        "sidebar.rows": "行数",
        "sidebar.presets": "预设",
        "sidebar.presetName": "预设名称",
        "sidebar.save": "保存",
        "sidebar.saveCurrentLayout": "保存当前布局",
        "sidebar.import": "导入",
        "sidebar.export": "导出",
        "sidebar.noSavedPresets": "没有保存的预设。",
        "sidebar.export.title": "导出",
        "sidebar.export.subtitle": "透明浮层渲染设置",
        "sidebar.render": "渲染",
        "sidebar.exportingOverlay": "正在导出浮层",
        "sidebar.exportProgress": "导出进度",
        "sidebar.exportDisabled": "导出不可用",
        "sidebar.exportOverlay": "导出浮层",

        "preset.default": "默认",
        "preset.gaugeCount": "%d 个浮层",
        "preset.apply": "应用",
        "preset.applyHelp": "应用预设",
        "preset.setDefault": "设为默认",
        "preset.setDefaultHelp": "设为默认预设",
        "preset.delete": "删除",
        "preset.deleteHelp": "删除预设",
        "preset.deleteDialogTitle": "删除布局预设？",
        "preset.deleteNamed": "删除 %@",
        "preset.deleteDialogMessage": "这会移除已保存的预设，不会改变当前画布布局。",
        "common.cancel": "取消",

        "inspector.noSelection.title": "未选择浮层",
        "inspector.noSelection.subtitle": "点击预览中的浮层",
        "inspector.noSelection.message": "点击预览画布中的可见浮层，或添加新元素。",
        "inspector.addElement": "添加元素",
        "inspector.duplicate": "复制选中元素",
        "inspector.sendBackward": "将选中元素下移一层",
        "inspector.bringForward": "将选中元素上移一层",
        "inspector.delete": "删除选中元素",
        "inspector.visible": "显示",
        "inspector.size": "大小",
        "inspector.length": "长度",
        "inspector.label": "标签",
        "inspector.labelText": "标签文字",
        "inspector.endLabel": "终点标签",
        "inspector.clockAndDate": "时间和日期",
        "inspector.unit": "单位",
        "inspector.unitText": "单位文字",
        "inspector.icon": "图标",
        "inspector.iconText": "图标文字",
        "inspector.panel": "面板",
        "inspector.panelBorder": "面板边框",
        "inspector.panelOpacity": "面板透明度",
        "inspector.gaugeWidth": "仪表宽度",
        "inspector.lineWidth": "线宽",
        "inspector.trackColor": "轨道颜色",
        "inspector.progressColor": "进度颜色",
        "inspector.sidePadding": "侧边距",
        "inspector.knobSize": "滑块大小",
        "inspector.valueMargin": "数值间距",
        "inspector.tickMarks": "刻度线",
        "inspector.tickCount": "刻度数量",
        "inspector.value": "数值",
        "inspector.decimals": "小数位：%d",
        "inspector.gaugeTicks": "仪表刻度",
        "inspector.gaugeMin": "仪表最小值",
        "inspector.gaugeMax": "仪表最大值",
        "inspector.layout": "布局",
        "inspector.appearance": "外观",
        "inspector.content": "内容",
        "inspector.typography": "字体",
        "inspector.data": "数据",
        "inspector.font": "字体",
        "inspector.color": "颜色",
        "inspector.fontSize": "字号",

        "preview.time": "预览 %@",
        "preview.sportStartAt": "运动开始：%@",
        "preview.warning": "预览警告",
        "preview.play": "播放",
        "preview.pause": "暂停",
        "preview.zoomOut": "缩小",
        "preview.zoomOutHelp": "缩小预览",
        "preview.zoomIn": "放大",
        "preview.zoomInHelp": "放大预览",
        "preview.fit": "适配",
        "preview.fitHelp": "适配到预览区域",
        "preview.exitFullscreen": "退出全屏",
        "preview.fullscreen": "全屏",
        "preview.exitFullscreenHelp": "退出全屏",
        "preview.fullscreenHelp": "全屏预览",
        "preview.placeholder.title": "选择视频和 FIT 文件",
        "preview.placeholder.subtitle": "预览加载后可以拖动和调整浮层。",
        "preview.selected": "已选择",
        "preview.notSelected": "未选择",
        "preview.elementHint": "点击选择。拖动移动。",

        "sync.offset": "手动",
        "sync.fitStart": "视频开头",
        "sync.syncPoint": "匹配点",

        "component.speed": "速度",
        "component.pace": "配速",
        "component.heartRate": "心率",
        "component.cadence": "步频",
        "component.distanceValue": "距离数值",
        "component.gpsRoute": "GPS 轨迹",
        "component.distance": "距离",
        "component.timeDate": "时间和日期",

        "codec.hevcAlpha": "带透明通道的 HEVC/H.265",
        "codec.proRes4444": "Apple ProRes 4444",
        "unit.meters": "米 (m)",
        "unit.kilometers": "公里 (km)",

        "status.chooseVideoAndFit": "请选择视频和 FIT 文件。",
        "status.chooseSourceVideo": "请选择源视频。",
        "status.chooseFitFile": "请选择 FIT 文件。",
        "status.outputWidthRange": "输出宽度需要在 2 到 16,384 px 之间。",
        "status.outputWidthEven": "输出宽度需要是偶数像素。",
        "status.outputHeightRange": "输出高度需要在 2 到 16,384 px 之间。",
        "status.outputHeightEven": "输出高度需要是偶数像素。",
        "status.frameRateRange": "帧率需要在 1 到 240 fps 之间。",
        "status.durationRange": "时长需要在 0.1 秒到 24 小时之间。",
        "status.bitrateRange": "码率需要在 1 到 1,000,000 kbps 之间。",
        "status.bitrateTooLarge": "这个 Mac 无法使用这么大的码率。",
        "status.exportCancelled": "导出已取消。",
        "status.presetNameRequired": "需要填写预设名称。",
        "status.updatedPreset": "已更新布局预设：%@",
        "status.savedPreset": "已保存布局预设：%@",
        "status.appliedPreset": "已应用布局预设：%@",
        "status.defaultPreset": "默认布局预设：%@",
        "status.deletedPreset": "已删除布局预设：%@",
        "status.noPresetsToExport": "没有可导出的布局预设。",
        "status.exportedPresets": "已导出 %d 个布局预设。",
        "status.presetExportError": "预设导出错误：%@",
        "status.noPresetsImported": "没有导入布局预设。",
        "status.importedPresets": "已导入 %d 个布局预设。",
        "status.presetImportError": "预设导入错误：%@",
        "status.loadingVideo": "正在加载视频：%@",
        "status.loadedVideo": "已加载视频：%@",
        "status.videoError": "视频错误：%@",
        "status.sportStartSet": "运动开始已设置在视频 %@；运动时间从 00:00 开始。",
        "status.loadingFit": "正在加载 FIT：%@",
        "status.loadedFit": "已加载 FIT：%@",
        "status.fitError": "FIT 错误：%@",
        "status.previewVideoFailed": "视频帧预览失败",
        "status.previewOverlayFailed": "浮层预览失败",
        "status.checkOutputSettings": "请检查输出设置：宽高、帧率和码率都需要在有效范围内。",
        "status.chooseOutputFile": "请选择导出文件。",
        "status.chooseFitBeforeExport": "导出前请选择 FIT 文件。",
        "status.exporting": "正在导出...",
        "status.wroteFile": "已写入 %@",
        "status.exportError": "导出错误：%@",
        "status.cancellingExport": "正在取消导出...",

        "panel.chooseSourceVideo": "选择源视频",
        "panel.chooseFitActivity": "选择 FIT 运动数据",
        "panel.saveOverlayVideo": "保存透明浮层视频",
        "panel.exportLayoutPresets": "导出布局预设",
        "panel.importLayoutPresets": "导入布局预设"
    ]

    private static let traditionalChinese: [String: String] = [
        "app.name": "DataLayer Studio",
        "language.system": "跟隨系統",
        "settings.general": "一般",
        "settings.language.title": "語言",
        "settings.language.picker": "App 語言",
        "settings.language.description": "預設跟隨系統語言。手動選擇後會立即生效。",

        "menu.openVideo": "打開影片...",
        "menu.openFit": "打開 FIT...",
        "menu.exportOverlay": "匯出浮層...",
        "menu.cancelExport": "取消匯出",
        "menu.arrange": "排列",
        "menu.bringForward": "上移一層",
        "menu.sendBackward": "下移一層",
        "menu.preview": "預覽",
        "menu.refreshPreview": "重新整理預覽",
        "menu.pausePreview": "暫停預覽",
        "menu.playPreview": "播放預覽",
        "menu.setSportStart": "設定運動開始",
        "menu.zoomIn": "放大",
        "menu.zoomOut": "縮小",
        "menu.resetZoom": "重設縮放",
        "menu.exitPreviewFullscreen": "離開預覽全螢幕",
        "menu.enterPreviewFullscreen": "進入預覽全螢幕",

        "toolbar.refreshPreview": "重新整理預覽",
        "toolbar.sportStart": "運動開始",
        "toolbar.output": "輸出",
        "toolbar.cancelExport": "取消匯出",
        "toolbar.export": "匯出",
        "help.cancelExport": "取消匯出",
        "help.exportTransparentOverlay": "匯出透明浮層影片",

        "sidebar.workflowTabs": "工作流程步驟",
        "sidebar.source.title": "素材",
        "sidebar.source.subtitle": "影片和 FIT 運動資料",
        "sidebar.video.title": "影片",
        "sidebar.video.placeholder": "選擇來源影片",
        "sidebar.fit.title": "FIT",
        "sidebar.fit.placeholder": "選擇 activity.fit",
        "sidebar.sync.title": "同步",
        "sidebar.sync.subtitle": "匹配影片時間和運動時間",
        "sidebar.mode": "模式",
        "sidebar.sportStart": "運動開始",
        "sidebar.offset": "偏移",
        "sidebar.offset.description": "正數表示影片早於 FIT 開始。負數表示影片從運動中途開始。",
        "sidebar.videoZeroFit": "影片 0 = FIT",
        "sidebar.videoPoint": "影片點",
        "sidebar.fitPoint": "FIT 點",
        "sidebar.sync.mode": "同步方式",
        "sidebar.sync.currentFrame": "目前預覽",
        "sidebar.sync.currentMapping": "影片 %@ = 運動 %@",
        "sidebar.sync.beforeActivity": "運動開始前 %@",
        "sidebar.sync.setCurrentAsStart": "目前畫面就是運動開始",
        "sidebar.sync.setCurrentAsStartHelp": "先把播放頭拖到開表那一格，再點這裡。它會把這個影片時間設為運動 00:00。",
        "sidebar.sync.videoTime": "影片",
        "sidebar.sync.activityTime": "運動",
        "sidebar.sync.matchHelp": "當你能在影片和運動資料裡找到同一個瞬間時，用這個方式最直覺。",
        "sidebar.sync.activityAtVideoStart": "00:00 時",
        "sidebar.sync.whenToUse": "適用場景",
        "sidebar.sync.videoStartHelp": "如果錄影開始時運動已經進行了一段時間，輸入影片 00:00 對應的運動用時。",
        "sidebar.sync.manualOffset": "偏移",
        "sidebar.sync.time.sign": "正負",
        "sidebar.sync.time.hours": "時",
        "sidebar.sync.time.minutes": "分",
        "sidebar.sync.time.seconds": "秒",
        "sidebar.sync.offsetResult": "結果",
        "sidebar.sync.offsetAligned": "影片 00:00 和運動 00:00 已對齊。",
        "sidebar.sync.offsetVideoBeforeFit": "運動在影片開始 %@ 後開始。",
        "sidebar.sync.offsetVideoAfterFit": "影片在運動開始 %@ 後開始。",
        "sidebar.sync.manualOffsetHelp": "進階模式。正數表示運動在影片中稍後開始；負數表示影片從運動中途開始。",
        "sidebar.canvas.title": "畫布",
        "sidebar.canvas.subtitle": "預覽網格和可重用浮層布局",
        "sidebar.videoSettings": "影片",
        "sidebar.resolution": "解析度",
        "sidebar.sourceResolutionPreset": "來源影片 %d×%d",
        "sidebar.custom": "自訂",
        "sidebar.width": "寬度",
        "sidebar.height": "高度",
        "sidebar.frameRate": "影格率",
        "sidebar.sourceFrameRatePreset": "來源影片 %@ fps",
        "sidebar.fps": "影格率",
        "sidebar.duration": "時長",
        "sidebar.bitrate": "位元率",
        "sidebar.distanceUnit": "距離單位",
        "sidebar.codec": "編碼",
        "sidebar.destination": "目標",
        "sidebar.saveAs": "另存為",
        "sidebar.askWhenExporting": "匯出時詢問",
        "sidebar.grid": "網格",
        "sidebar.showGrid": "顯示網格",
        "sidebar.snapWhileDragging": "拖曳時吸附",
        "sidebar.columns": "欄數",
        "sidebar.rows": "列數",
        "sidebar.presets": "預設",
        "sidebar.presetName": "預設名稱",
        "sidebar.save": "儲存",
        "sidebar.saveCurrentLayout": "儲存目前布局",
        "sidebar.import": "匯入",
        "sidebar.export": "匯出",
        "sidebar.noSavedPresets": "沒有儲存的預設。",
        "sidebar.export.title": "匯出",
        "sidebar.export.subtitle": "透明浮層渲染設定",
        "sidebar.render": "渲染",
        "sidebar.exportingOverlay": "正在匯出浮層",
        "sidebar.exportProgress": "匯出進度",
        "sidebar.exportDisabled": "匯出不可用",
        "sidebar.exportOverlay": "匯出浮層",

        "preset.default": "預設",
        "preset.gaugeCount": "%d 個浮層",
        "preset.apply": "套用",
        "preset.applyHelp": "套用預設",
        "preset.setDefault": "設為預設",
        "preset.setDefaultHelp": "設為預設布局",
        "preset.delete": "刪除",
        "preset.deleteHelp": "刪除預設",
        "preset.deleteDialogTitle": "刪除布局預設？",
        "preset.deleteNamed": "刪除 %@",
        "preset.deleteDialogMessage": "這會移除已儲存的預設，不會改變目前畫布布局。",
        "common.cancel": "取消",

        "inspector.noSelection.title": "未選擇浮層",
        "inspector.noSelection.subtitle": "點擊預覽中的浮層",
        "inspector.noSelection.message": "點擊預覽畫布中的可見浮層，或新增元素。",
        "inspector.addElement": "新增元素",
        "inspector.duplicate": "複製選中元素",
        "inspector.sendBackward": "將選中元素下移一層",
        "inspector.bringForward": "將選中元素上移一層",
        "inspector.delete": "刪除選中元素",
        "inspector.visible": "顯示",
        "inspector.size": "大小",
        "inspector.length": "長度",
        "inspector.label": "標籤",
        "inspector.labelText": "標籤文字",
        "inspector.endLabel": "終點標籤",
        "inspector.clockAndDate": "時間和日期",
        "inspector.unit": "單位",
        "inspector.unitText": "單位文字",
        "inspector.icon": "圖示",
        "inspector.iconText": "圖示文字",
        "inspector.panel": "面板",
        "inspector.panelBorder": "面板邊框",
        "inspector.panelOpacity": "面板透明度",
        "inspector.gaugeWidth": "儀表寬度",
        "inspector.lineWidth": "線寬",
        "inspector.trackColor": "軌道顏色",
        "inspector.progressColor": "進度顏色",
        "inspector.sidePadding": "側邊距",
        "inspector.knobSize": "滑塊大小",
        "inspector.valueMargin": "數值間距",
        "inspector.tickMarks": "刻度線",
        "inspector.tickCount": "刻度數量",
        "inspector.value": "數值",
        "inspector.decimals": "小數位：%d",
        "inspector.gaugeTicks": "儀表刻度",
        "inspector.gaugeMin": "儀表最小值",
        "inspector.gaugeMax": "儀表最大值",
        "inspector.layout": "布局",
        "inspector.appearance": "外觀",
        "inspector.content": "內容",
        "inspector.typography": "字體",
        "inspector.data": "資料",
        "inspector.font": "字體",
        "inspector.color": "顏色",
        "inspector.fontSize": "字號",

        "preview.time": "預覽 %@",
        "preview.sportStartAt": "運動開始：%@",
        "preview.warning": "預覽警告",
        "preview.play": "播放",
        "preview.pause": "暫停",
        "preview.zoomOut": "縮小",
        "preview.zoomOutHelp": "縮小預覽",
        "preview.zoomIn": "放大",
        "preview.zoomInHelp": "放大預覽",
        "preview.fit": "適配",
        "preview.fitHelp": "適配到預覽區域",
        "preview.exitFullscreen": "離開全螢幕",
        "preview.fullscreen": "全螢幕",
        "preview.exitFullscreenHelp": "離開全螢幕",
        "preview.fullscreenHelp": "全螢幕預覽",
        "preview.placeholder.title": "選擇影片和 FIT 檔案",
        "preview.placeholder.subtitle": "預覽載入後可以拖曳和調整浮層。",
        "preview.selected": "已選擇",
        "preview.notSelected": "未選擇",
        "preview.elementHint": "點擊選擇。拖曳移動。",

        "sync.offset": "手動",
        "sync.fitStart": "影片開頭",
        "sync.syncPoint": "匹配點",

        "component.speed": "速度",
        "component.pace": "配速",
        "component.heartRate": "心率",
        "component.cadence": "步頻",
        "component.distanceValue": "距離數值",
        "component.gpsRoute": "GPS 軌跡",
        "component.distance": "距離",
        "component.timeDate": "時間和日期",

        "codec.hevcAlpha": "帶透明通道的 HEVC/H.265",
        "codec.proRes4444": "Apple ProRes 4444",
        "unit.meters": "公尺 (m)",
        "unit.kilometers": "公里 (km)",

        "status.chooseVideoAndFit": "請選擇影片和 FIT 檔案。",
        "status.chooseSourceVideo": "請選擇來源影片。",
        "status.chooseFitFile": "請選擇 FIT 檔案。",
        "status.outputWidthRange": "輸出寬度需要在 2 到 16,384 px 之間。",
        "status.outputWidthEven": "輸出寬度需要是偶數像素。",
        "status.outputHeightRange": "輸出高度需要在 2 到 16,384 px 之間。",
        "status.outputHeightEven": "輸出高度需要是偶數像素。",
        "status.frameRateRange": "影格率需要在 1 到 240 fps 之間。",
        "status.durationRange": "時長需要在 0.1 秒到 24 小時之間。",
        "status.bitrateRange": "位元率需要在 1 到 1,000,000 kbps 之間。",
        "status.bitrateTooLarge": "這台 Mac 無法使用這麼大的位元率。",
        "status.exportCancelled": "匯出已取消。",
        "status.presetNameRequired": "需要填寫預設名稱。",
        "status.updatedPreset": "已更新布局預設：%@",
        "status.savedPreset": "已儲存布局預設：%@",
        "status.appliedPreset": "已套用布局預設：%@",
        "status.defaultPreset": "預設布局：%@",
        "status.deletedPreset": "已刪除布局預設：%@",
        "status.noPresetsToExport": "沒有可匯出的布局預設。",
        "status.exportedPresets": "已匯出 %d 個布局預設。",
        "status.presetExportError": "預設匯出錯誤：%@",
        "status.noPresetsImported": "沒有匯入布局預設。",
        "status.importedPresets": "已匯入 %d 個布局預設。",
        "status.presetImportError": "預設匯入錯誤：%@",
        "status.loadingVideo": "正在載入影片：%@",
        "status.loadedVideo": "已載入影片：%@",
        "status.videoError": "影片錯誤：%@",
        "status.sportStartSet": "運動開始已設定在影片 %@；運動時間從 00:00 開始。",
        "status.loadingFit": "正在載入 FIT：%@",
        "status.loadedFit": "已載入 FIT：%@",
        "status.fitError": "FIT 錯誤：%@",
        "status.previewVideoFailed": "影片影格預覽失敗",
        "status.previewOverlayFailed": "浮層預覽失敗",
        "status.checkOutputSettings": "請檢查輸出設定：寬高、影格率和位元率都需要在有效範圍內。",
        "status.chooseOutputFile": "請選擇匯出檔案。",
        "status.chooseFitBeforeExport": "匯出前請選擇 FIT 檔案。",
        "status.exporting": "正在匯出...",
        "status.wroteFile": "已寫入 %@",
        "status.exportError": "匯出錯誤：%@",
        "status.cancellingExport": "正在取消匯出...",

        "panel.chooseSourceVideo": "選擇來源影片",
        "panel.chooseFitActivity": "選擇 FIT 運動資料",
        "panel.saveOverlayVideo": "儲存透明浮層影片",
        "panel.exportLayoutPresets": "匯出布局預設",
        "panel.importLayoutPresets": "匯入布局預設"
    ]

    private static let japanese: [String: String] = [
        "app.name": "DataLayer Studio",
        "language.system": "システムに合わせる",
        "settings.general": "一般",
        "settings.language.title": "言語",
        "settings.language.picker": "アプリの言語",
        "settings.language.description": "既定ではシステム言語に従います。手動選択はすぐに反映されます。",

        "menu.openVideo": "動画を開く...",
        "menu.openFit": "FIT を開く...",
        "menu.exportOverlay": "オーバーレイを書き出す...",
        "menu.cancelExport": "書き出しをキャンセル",
        "menu.arrange": "配置",
        "menu.bringForward": "前面へ",
        "menu.sendBackward": "背面へ",
        "menu.preview": "プレビュー",
        "menu.refreshPreview": "プレビューを更新",
        "menu.pausePreview": "プレビューを一時停止",
        "menu.playPreview": "プレビューを再生",
        "menu.setSportStart": "運動開始を設定",
        "menu.zoomIn": "拡大",
        "menu.zoomOut": "縮小",
        "menu.resetZoom": "ズームをリセット",
        "menu.exitPreviewFullscreen": "プレビューのフルスクリーンを終了",
        "menu.enterPreviewFullscreen": "プレビューをフルスクリーン表示",

        "toolbar.refreshPreview": "プレビューを更新",
        "toolbar.sportStart": "運動開始",
        "toolbar.output": "出力",
        "toolbar.cancelExport": "書き出しをキャンセル",
        "toolbar.export": "書き出し",
        "help.cancelExport": "書き出しをキャンセル",
        "help.exportTransparentOverlay": "透明オーバーレイ動画を書き出す",

        "sidebar.workflowTabs": "ワークフロー手順",
        "sidebar.source.title": "ソース",
        "sidebar.source.subtitle": "動画と FIT アクティビティデータ",
        "sidebar.video.title": "動画",
        "sidebar.video.placeholder": "ソース動画を選択",
        "sidebar.fit.title": "FIT",
        "sidebar.fit.placeholder": "activity.fit を選択",
        "sidebar.sync.title": "同期",
        "sidebar.sync.subtitle": "動画時間とアクティビティ時間を合わせる",
        "sidebar.mode": "モード",
        "sidebar.sportStart": "運動開始",
        "sidebar.offset": "オフセット",
        "sidebar.offset.description": "正の値は動画が FIT より先に始まることを示します。負の値は運動途中から録画したことを示します。",
        "sidebar.videoZeroFit": "動画 0 = FIT",
        "sidebar.videoPoint": "動画の時刻",
        "sidebar.fitPoint": "FIT の時刻",
        "sidebar.sync.mode": "同期方法",
        "sidebar.sync.currentFrame": "現在のプレビュー",
        "sidebar.sync.currentMapping": "動画 %@ = アクティビティ %@",
        "sidebar.sync.beforeActivity": "開始 %@ 前",
        "sidebar.sync.setCurrentAsStart": "現在のフレームを運動開始にする",
        "sidebar.sync.setCurrentAsStartHelp": "時計を開始したフレームまで移動してからクリックします。その動画時刻をアクティビティ 00:00 に設定します。",
        "sidebar.sync.videoTime": "動画",
        "sidebar.sync.activityTime": "運動",
        "sidebar.sync.matchHelp": "動画とアクティビティで同じ瞬間が分かる場合に使います。",
        "sidebar.sync.activityAtVideoStart": "00:00 の運動",
        "sidebar.sync.whenToUse": "使いどころ",
        "sidebar.sync.videoStartHelp": "録画開始時点で運動がすでに始まっている場合に使います。動画 00:00 に対応する運動時間を入力してください。",
        "sidebar.sync.manualOffset": "オフセット",
        "sidebar.sync.time.sign": "符号",
        "sidebar.sync.time.hours": "時",
        "sidebar.sync.time.minutes": "分",
        "sidebar.sync.time.seconds": "秒",
        "sidebar.sync.offsetResult": "結果",
        "sidebar.sync.offsetAligned": "動画 00:00 と運動 00:00 が一致しています。",
        "sidebar.sync.offsetVideoBeforeFit": "運動は動画開始から %@ 後に始まります。",
        "sidebar.sync.offsetVideoAfterFit": "動画は運動開始から %@ 後に始まります。",
        "sidebar.sync.manualOffsetHelp": "上級者向け。正の値は運動が動画内で後から始まること、負の値は動画が運動途中から始まることを示します。",
        "sidebar.canvas.title": "キャンバス",
        "sidebar.canvas.subtitle": "プレビューグリッドと再利用できるゲージ配置",
        "sidebar.videoSettings": "動画",
        "sidebar.resolution": "解像度",
        "sidebar.sourceResolutionPreset": "ソース動画 %d×%d",
        "sidebar.custom": "カスタム",
        "sidebar.width": "幅",
        "sidebar.height": "高さ",
        "sidebar.frameRate": "フレームレート",
        "sidebar.sourceFrameRatePreset": "ソース動画 %@ fps",
        "sidebar.fps": "フレームレート",
        "sidebar.duration": "長さ",
        "sidebar.bitrate": "ビットレート",
        "sidebar.distanceUnit": "距離単位",
        "sidebar.codec": "コーデック",
        "sidebar.destination": "保存先",
        "sidebar.saveAs": "別名で保存",
        "sidebar.askWhenExporting": "書き出し時に確認",
        "sidebar.grid": "グリッド",
        "sidebar.showGrid": "グリッドを表示",
        "sidebar.snapWhileDragging": "ドラッグ中にスナップ",
        "sidebar.columns": "列",
        "sidebar.rows": "行",
        "sidebar.presets": "プリセット",
        "sidebar.presetName": "プリセット名",
        "sidebar.save": "保存",
        "sidebar.saveCurrentLayout": "現在の配置を保存",
        "sidebar.import": "読み込み",
        "sidebar.export": "書き出し",
        "sidebar.noSavedPresets": "保存済みプリセットはありません。",
        "sidebar.export.title": "書き出し",
        "sidebar.export.subtitle": "透明オーバーレイのレンダー設定",
        "sidebar.render": "レンダー",
        "sidebar.exportingOverlay": "オーバーレイを書き出し中",
        "sidebar.exportProgress": "書き出しの進行状況",
        "sidebar.exportDisabled": "書き出し不可",
        "sidebar.exportOverlay": "オーバーレイを書き出す",

        "preset.default": "既定",
        "preset.gaugeCount": "%d 個のゲージ",
        "preset.apply": "適用",
        "preset.applyHelp": "プリセットを適用",
        "preset.setDefault": "既定にする",
        "preset.setDefaultHelp": "既定のプリセットにする",
        "preset.delete": "削除",
        "preset.deleteHelp": "プリセットを削除",
        "preset.deleteDialogTitle": "配置プリセットを削除しますか？",
        "preset.deleteNamed": "%@ を削除",
        "preset.deleteDialogMessage": "保存済みプリセットを削除します。現在のキャンバス配置は変更されません。",
        "common.cancel": "キャンセル",

        "inspector.noSelection.title": "要素が選択されていません",
        "inspector.noSelection.subtitle": "プレビュー内のゲージをクリック",
        "inspector.noSelection.message": "プレビューキャンバス内の表示中ゲージをクリックするか、新しい要素を追加してください。",
        "inspector.addElement": "要素を追加",
        "inspector.duplicate": "選択要素を複製",
        "inspector.sendBackward": "選択要素を背面へ",
        "inspector.bringForward": "選択要素を前面へ",
        "inspector.delete": "選択要素を削除",
        "inspector.visible": "表示",
        "inspector.size": "サイズ",
        "inspector.length": "長さ",
        "inspector.label": "ラベル",
        "inspector.labelText": "ラベル文字",
        "inspector.endLabel": "終了ラベル",
        "inspector.clockAndDate": "時刻と日付",
        "inspector.unit": "単位",
        "inspector.unitText": "単位文字",
        "inspector.icon": "アイコン",
        "inspector.iconText": "アイコン文字",
        "inspector.panel": "パネル",
        "inspector.panelBorder": "パネル枠線",
        "inspector.panelOpacity": "パネル不透明度",
        "inspector.gaugeWidth": "ゲージ幅",
        "inspector.lineWidth": "線幅",
        "inspector.trackColor": "トラック色",
        "inspector.progressColor": "進行色",
        "inspector.sidePadding": "左右余白",
        "inspector.knobSize": "ノブサイズ",
        "inspector.valueMargin": "値の余白",
        "inspector.tickMarks": "目盛り",
        "inspector.tickCount": "目盛り数",
        "inspector.value": "値",
        "inspector.decimals": "小数桁：%d",
        "inspector.gaugeTicks": "ゲージ目盛り",
        "inspector.gaugeMin": "ゲージ最小値",
        "inspector.gaugeMax": "ゲージ最大値",
        "inspector.layout": "レイアウト",
        "inspector.appearance": "外観",
        "inspector.content": "内容",
        "inspector.typography": "タイポグラフィ",
        "inspector.data": "データ",
        "inspector.font": "フォント",
        "inspector.color": "カラー",
        "inspector.fontSize": "フォントサイズ",

        "preview.time": "プレビュー %@",
        "preview.sportStartAt": "運動開始：%@",
        "preview.warning": "プレビュー警告",
        "preview.play": "再生",
        "preview.pause": "一時停止",
        "preview.zoomOut": "縮小",
        "preview.zoomOutHelp": "プレビューを縮小",
        "preview.zoomIn": "拡大",
        "preview.zoomInHelp": "プレビューを拡大",
        "preview.fit": "合わせる",
        "preview.fitHelp": "プレビューに合わせる",
        "preview.exitFullscreen": "フルスクリーンを終了",
        "preview.fullscreen": "フルスクリーン",
        "preview.exitFullscreenHelp": "フルスクリーンを終了",
        "preview.fullscreenHelp": "フルスクリーンプレビュー",
        "preview.placeholder.title": "動画と FIT ファイルを選択",
        "preview.placeholder.subtitle": "プレビュー読み込み後にオーバーレイをドラッグ、サイズ変更できます。",
        "preview.selected": "選択済み",
        "preview.notSelected": "未選択",
        "preview.elementHint": "クリックで選択。ドラッグで移動。",

        "sync.offset": "手動",
        "sync.fitStart": "動画開始",
        "sync.syncPoint": "時刻合わせ",

        "component.speed": "速度",
        "component.pace": "ペース",
        "component.heartRate": "心拍数",
        "component.cadence": "ピッチ",
        "component.distanceValue": "距離の値",
        "component.gpsRoute": "GPS ルート",
        "component.distance": "距離",
        "component.timeDate": "時刻と日付",

        "codec.hevcAlpha": "アルファ付き HEVC/H.265",
        "codec.proRes4444": "Apple ProRes 4444",
        "unit.meters": "メートル (m)",
        "unit.kilometers": "キロメートル (km)",

        "status.chooseVideoAndFit": "動画と FIT ファイルを選択してください。",
        "status.chooseSourceVideo": "ソース動画を選択してください。",
        "status.chooseFitFile": "FIT ファイルを選択してください。",
        "status.outputWidthRange": "出力幅は 2 から 16,384 px の範囲にしてください。",
        "status.outputWidthEven": "出力幅は偶数ピクセルにしてください。",
        "status.outputHeightRange": "出力高さは 2 から 16,384 px の範囲にしてください。",
        "status.outputHeightEven": "出力高さは偶数ピクセルにしてください。",
        "status.frameRateRange": "フレームレートは 1 から 240 fps の範囲にしてください。",
        "status.durationRange": "長さは 0.1 秒から 24 時間の範囲にしてください。",
        "status.bitrateRange": "ビットレートは 1 から 1,000,000 kbps の範囲にしてください。",
        "status.bitrateTooLarge": "この Mac にはビットレートが大きすぎます。",
        "status.exportCancelled": "書き出しをキャンセルしました。",
        "status.presetNameRequired": "プリセット名が必要です。",
        "status.updatedPreset": "配置プリセットを更新しました：%@",
        "status.savedPreset": "配置プリセットを保存しました：%@",
        "status.appliedPreset": "配置プリセットを適用しました：%@",
        "status.defaultPreset": "既定の配置プリセット：%@",
        "status.deletedPreset": "配置プリセットを削除しました：%@",
        "status.noPresetsToExport": "書き出す配置プリセットがありません。",
        "status.exportedPresets": "%d 個の配置プリセットを書き出しました。",
        "status.presetExportError": "プリセット書き出しエラー：%@",
        "status.noPresetsImported": "配置プリセットは読み込まれませんでした。",
        "status.importedPresets": "%d 個の配置プリセットを読み込みました。",
        "status.presetImportError": "プリセット読み込みエラー：%@",
        "status.loadingVideo": "動画を読み込み中：%@",
        "status.loadedVideo": "動画を読み込みました：%@",
        "status.videoError": "動画エラー：%@",
        "status.sportStartSet": "運動開始を動画 %@ に設定しました。運動時間は 00:00 から始まります。",
        "status.loadingFit": "FIT を読み込み中：%@",
        "status.loadedFit": "FIT を読み込みました：%@",
        "status.fitError": "FIT エラー：%@",
        "status.previewVideoFailed": "動画フレームのプレビューに失敗しました",
        "status.previewOverlayFailed": "オーバーレイのプレビューに失敗しました",
        "status.checkOutputSettings": "出力設定を確認してください：幅/高さ、fps、ビットレートは有効範囲内である必要があります。",
        "status.chooseOutputFile": "書き出し先ファイルを選択してください。",
        "status.chooseFitBeforeExport": "書き出し前に FIT ファイルを選択してください。",
        "status.exporting": "書き出し中...",
        "status.wroteFile": "%@ に書き込みました",
        "status.exportError": "書き出しエラー：%@",
        "status.cancellingExport": "書き出しをキャンセル中...",

        "panel.chooseSourceVideo": "ソース動画を選択",
        "panel.chooseFitActivity": "FIT アクティビティを選択",
        "panel.saveOverlayVideo": "透明オーバーレイ動画を保存",
        "panel.exportLayoutPresets": "配置プリセットを書き出す",
        "panel.importLayoutPresets": "配置プリセットを読み込む"
    ]
}

extension SyncMode {
    var localizationKey: String {
        switch self {
        case .offset:
            return "sync.offset"
        case .fitStart:
            return "sync.fitStart"
        case .syncPoint:
            return "sync.syncPoint"
        }
    }
}

extension OverlayComponentID {
    var localizationKey: String {
        switch self {
        case .speed:
            return "component.speed"
        case .pace:
            return "component.pace"
        case .heartRate:
            return "component.heartRate"
        case .cadence:
            return "component.cadence"
        case .distance:
            return "component.distanceValue"
        case .route:
            return "component.gpsRoute"
        case .topProgress:
            return "component.distance"
        case .timeDate:
            return "component.timeDate"
        }
    }
}

extension OverlayVideoCodec {
    var localizationKey: String {
        switch self {
        case .hevcAlpha:
            return "codec.hevcAlpha"
        case .proRes4444:
            return "codec.proRes4444"
        }
    }
}

extension OverlayDistanceUnit {
    var localizationKey: String {
        switch self {
        case .meters:
            return "unit.meters"
        case .kilometers:
            return "unit.kilometers"
        }
    }
}
