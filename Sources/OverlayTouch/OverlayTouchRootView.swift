import OverlayCore
import OverlayStudioKit
import SwiftUI

/// 对外入口：iOS 上进入 iPad 编辑器，macOS 构建保留 P0 诊断视图。
public struct OverlayTouchRootView: View {
    public init() {}

    public var body: some View {
        #if os(iOS)
        TouchEditorRootView()
        #else
        OverlayTouchDiagnosticsView()
        #endif
    }
}

struct OverlayTouchDiagnosticsView: View {
    private let diagnostics: OverlayTouchDiagnostics
    @Environment(\.locale) private var locale

    init(diagnostics: OverlayTouchDiagnostics = .current) {
        self.diagnostics = diagnostics
    }

    var body: some View {
        let strings = TouchStrings(locale: locale)

        ViewThatFits {
            regularLayout(strings: strings)
            compactLayout(strings: strings)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TouchPalette.background)
        .foregroundStyle(TouchPalette.primaryText)
    }

    private func regularLayout(strings: TouchStrings) -> some View {
        HStack(spacing: 16) {
            sourceColumn(strings: strings)
                .frame(width: 280)

            previewColumn(strings: strings)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            runtimeColumn(strings: strings)
                .frame(width: 300)
        }
    }

    private func compactLayout(strings: TouchStrings) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                previewColumn(strings: strings)
                    .frame(height: 360)
                sourceColumn(strings: strings)
                runtimeColumn(strings: strings)
            }
        }
    }

    private func sourceColumn(strings: TouchStrings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title(strings.appName, subtitle: strings.hostStatus, systemImage: "ipad")

            diagnosticRow(
                strings.coreStatusTitle,
                value: diagnostics.renderComponentCountText,
                systemImage: "square.3.layers.3d"
            )
            diagnosticRow(
                strings.kitStatusTitle,
                value: diagnostics.measuredTitleWidthText,
                systemImage: "textformat.size"
            )

            Spacer(minLength: 0)
        }
        .panelStyle()
    }

    private func previewColumn(strings: TouchStrings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title(strings.previewTitle, subtitle: strings.previewSubtitle, systemImage: "play.rectangle")

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(TouchPalette.previewFill)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(strings.paceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TouchPalette.secondaryText)
                            Text("4:32 /km")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                        }
                        .padding(18)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(strings.heartRateLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TouchPalette.secondaryText)
                            Text("156 bpm")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                        }
                        .padding(18)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(TouchPalette.border, lineWidth: 1)
                    )
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .panelStyle()
    }

    private func runtimeColumn(strings: TouchStrings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title(strings.runtimeTitle, subtitle: strings.runtimeSubtitle, systemImage: "cpu")

            diagnosticRow(
                strings.metalTitle,
                value: diagnostics.metalDeviceName,
                systemImage: "sparkle.magnifyingglass"
            )
            diagnosticRow(
                strings.encoderTitle,
                value: diagnostics.encoderSummary,
                systemImage: "video.badge.waveform"
            )
            diagnosticRow(
                strings.gpuFamilyTitle,
                value: diagnostics.gpuFamilyText,
                systemImage: "memorychip"
            )

            Spacer(minLength: 0)
        }
        .panelStyle()
    }

    private func title(_ text: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TouchPalette.secondaryText)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(TouchPalette.accent)
        }
    }

    private func diagnosticRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(TouchPalette.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TouchPalette.secondaryText)
                Text(value)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct OverlayTouchDiagnostics: Equatable, Sendable {
    public var metalDeviceName: String
    public var encoderSummary: String
    public var gpuFamilyText: String
    public var renderComponentCountText: String
    public var measuredTitleWidthText: String

    public init(
        metalDeviceName: String,
        encoderSummary: String,
        gpuFamilyText: String,
        renderComponentCountText: String,
        measuredTitleWidthText: String
    ) {
        self.metalDeviceName = metalDeviceName
        self.encoderSummary = encoderSummary
        self.gpuFamilyText = gpuFamilyText
        self.renderComponentCountText = renderComponentCountText
        self.measuredTitleWidthText = measuredTitleWidthText
    }

    public static var current: OverlayTouchDiagnostics {
        let profile = OverlayHardwareProfile.current
        let encoders = OverlayVideoCodec.allCases
            .filter { profile.canUseHardwareEncoder(for: $0) }
            .map(\.displayName)

        return OverlayTouchDiagnostics(
            metalDeviceName: profile.metalDeviceName ?? "-",
            encoderSummary: encoders.isEmpty ? "-" : encoders.joined(separator: " / "),
            gpuFamilyText: profile.highestSupportedAppleGPUFamily.map { "Apple \($0)" } ?? "-",
            renderComponentCountText: "\(OverlayLayout.default.elements.count)",
            measuredTitleWidthText: "\(Int(TextMeasurementCache.width("DataLayer Studio", size: 18, fontName: .helveticaNeueBold))) pt"
        )
    }
}

private struct TouchStrings {
    private let languageCode: String

    init(locale: Locale) {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh_hant")
            || identifier.hasPrefix("zh-hant")
            || identifier.hasPrefix("zh_tw")
            || identifier.hasPrefix("zh-tw")
            || identifier.hasPrefix("zh_hk")
            || identifier.hasPrefix("zh-hk") {
            languageCode = "zh-Hant"
        } else if identifier.hasPrefix("zh") {
            languageCode = "zh-Hans"
        } else if identifier.hasPrefix("ja") {
            languageCode = "ja"
        } else {
            languageCode = "en"
        }
    }

    var appName: String { value(en: "DataLayer Studio", zhHans: "DataLayer Studio", zhHant: "DataLayer Studio", ja: "DataLayer Studio") }
    var hostStatus: String { value(en: "iPad host is linked", zhHans: "iPad 入口已连通", zhHant: "iPad 入口已連通", ja: "iPad ホスト接続済み") }
    var coreStatusTitle: String { value(en: "Default components", zhHans: "默认组件", zhHant: "預設元件", ja: "標準コンポーネント") }
    var kitStatusTitle: String { value(en: "Shared text cache", zhHans: "共享文字缓存", zhHant: "共享文字快取", ja: "共有テキストキャッシュ") }
    var previewTitle: String { value(en: "Preview Shell", zhHans: "预览壳", zhHant: "預覽殼", ja: "プレビューシェル") }
    var previewSubtitle: String { value(en: "Ready for the shared editor", zhHans: "等待接入共享编辑器", zhHant: "等待接入共享編輯器", ja: "共有エディタ接続待ち") }
    var runtimeTitle: String { value(en: "Runtime", zhHans: "运行环境", zhHant: "執行環境", ja: "実行環境") }
    var runtimeSubtitle: String { value(en: "Device capability probe", zhHans: "设备能力探针", zhHant: "裝置能力探針", ja: "デバイス能力プローブ") }
    var metalTitle: String { value(en: "Metal", zhHans: "Metal", zhHant: "Metal", ja: "Metal") }
    var encoderTitle: String { value(en: "Encoders", zhHans: "编码器", zhHant: "編碼器", ja: "エンコーダ") }
    var gpuFamilyTitle: String { value(en: "GPU family", zhHans: "GPU 家族", zhHant: "GPU 家族", ja: "GPU ファミリー") }
    var paceLabel: String { value(en: "PACE", zhHans: "配速", zhHant: "配速", ja: "ペース") }
    var heartRateLabel: String { value(en: "HEART RATE", zhHans: "心率", zhHant: "心率", ja: "心拍数") }

    private func value(en: String, zhHans: String, zhHant: String, ja: String) -> String {
        switch languageCode {
        case "zh-Hans":
            return zhHans
        case "zh-Hant":
            return zhHant
        case "ja":
            return ja
        default:
            return en
        }
    }
}

private enum TouchPalette {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.075)
    static let panel = Color(red: 0.10, green: 0.105, blue: 0.105)
    static let previewFill = Color(red: 0.035, green: 0.04, blue: 0.045)
    static let border = Color.white.opacity(0.10)
    static let primaryText = Color(red: 0.92, green: 0.94, blue: 0.92)
    static let secondaryText = Color(red: 0.62, green: 0.66, blue: 0.65)
    static let accent = Color(red: 0.33, green: 0.83, blue: 0.70)
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(18)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(TouchPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TouchPalette.border, lineWidth: 1)
            )
    }
}

#Preview {
    OverlayTouchDiagnosticsView(
        diagnostics: OverlayTouchDiagnostics(
            metalDeviceName: "Apple M1",
            encoderSummary: "HEVC with Alpha / HEVC / H.264",
            gpuFamilyText: "Apple 8",
            renderComponentCountText: "21",
            measuredTitleWidthText: "142 pt"
        )
    )
}
