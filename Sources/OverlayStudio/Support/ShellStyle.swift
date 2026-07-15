import AppKit
import SwiftUI

/// 全局控制外壳（侧栏 · 控制条 · 工作区 · 检查器）共享的视觉令牌与基础组件。
/// 目标是一套清晰、有层次的卡片语言：可见的抬升表面 + 描边 + 柔和阴影，读起来高级。
enum ShellStyle {
    // 4pt 间距序列
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing6: CGFloat = 24
    static let spacing8: CGFloat = 32

    /// 抬升卡片填充：浅色下近白、深色下比面板明显亮一档，跨主题都能从 `.bar` 面板上浮起来。
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.11)
            : NSColor(calibratedWhite: 1, alpha: 0.94)
    })
    /// 卡片描边
    static let cardStroke = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.17)
            : NSColor(calibratedWhite: 0, alpha: 0.12)
    })
    /// 卡片阴影
    static let cardShadow = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(calibratedWhite: 0, alpha: isDark ? 0.52 : 0.16)
    })

    // 行内分隔线
    static let rowSeparator = Color.secondary.opacity(0.14)
    // 图标块 / 中性填充
    static let tileFill = Color.secondary.opacity(0.20)
    static let controlFill = Color.secondary.opacity(0.12)
    static let hoverFill = Color.secondary.opacity(0.09)
    // 强调
    static let accentSoft = Color.accentColor.opacity(0.20)
    static let accentStroke = Color.accentColor.opacity(0.42)

    // 圆角
    static let smallRadius: CGFloat = 6
    static let mediumRadius: CGFloat = 8
    static let largeRadius: CGFloat = 10
    static let groupRadius = largeRadius
    static let controlRadius = smallRadius
    static let tileRadius = mediumRadius
    static let pillRadius: CGFloat = 20

    static let tileSize: CGFloat = 28
}

extension View {
    /// 抬升卡片表面：实心填充 + 1px 描边 + 柔和阴影，替代几乎透明的发丝分组。
    func shellGroupSurface(cornerRadius: CGFloat = ShellStyle.groupRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ShellStyle.cardFill)
                .shadow(color: ShellStyle.cardShadow, radius: 7, x: 0, y: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ShellStyle.cardStroke, lineWidth: 1)
        }
    }
}

/// 圆角图标块：载入 / 选中态染强调色，否则中性灰。
struct ShellIconTile: View {
    var systemImage: String
    var isActive: Bool = false
    var size: CGFloat = ShellStyle.tileSize

    var body: some View {
        RoundedRectangle(cornerRadius: ShellStyle.tileRadius, style: .continuous)
            .fill(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(ShellStyle.tileFill))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(Color.secondary))
            }
            .shadow(color: isActive ? Color.accentColor.opacity(0.35) : .clear, radius: 4, y: 1)
    }
}

/// 胶囊状态芯片：已载入 / 待选 / 中性。
struct ShellStatusChip: View {
    enum Kind {
        case active
        case pending
        case neutral
    }

    var text: String
    var systemImage: String?
    var kind: Kind

    init(_ text: String, systemImage: String? = nil, kind: Kind = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.kind = kind
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(fill, in: Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .active:
            return .accentColor
        case .pending:
            return .secondary
        case .neutral:
            return .primary
        }
    }

    private var fill: Color {
        switch kind {
        case .active:
            return ShellStyle.accentSoft
        case .pending, .neutral:
            return ShellStyle.tileFill
        }
    }
}

/// 胶囊分段标签，与检查器范围栏（InspectorSectionScopeBar）视觉统一。
struct ShellSegmentedTabs: View {
    struct Tab: Identifiable {
        var id: String
        var title: String
        var systemImage: String?

        init(id: String, title: String, systemImage: String? = nil) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
        }
    }

    var tabs: [Tab]
    @Binding var selection: String
    var accessibilityLabel: String?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .background(ShellStyle.tileFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(ShellStyle.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selection == tab.id
        return Button {
            selection = tab.id
        } label: {
            HStack(spacing: 5) {
                if let systemImage = tab.systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(tab.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(isSelected ? ShellStyle.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? ShellStyle.accentStroke : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
