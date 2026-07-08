import SwiftUI

/// 全局控制外壳（侧栏 · 控制条 · 工作区 · 检查器）共享的视觉令牌与基础组件。
/// 目标是把检查器已有的克制描边语言铺满整个操作区域，避免毛玻璃卡片堆叠。
enum ShellStyle {
    // 分组表面
    static let groupFill = Color.secondary.opacity(0.026)
    static let groupStroke = Color.secondary.opacity(0.072)
    // 行内分隔线
    static let rowSeparator = Color.secondary.opacity(0.10)
    // 图标块 / 中性填充
    static let tileFill = Color.secondary.opacity(0.10)
    static let hoverFill = Color.secondary.opacity(0.045)
    // 强调
    static let accentSoft = Color.accentColor.opacity(0.12)
    static let accentStroke = Color.accentColor.opacity(0.30)

    // 圆角
    static let groupRadius: CGFloat = 10
    static let controlRadius: CGFloat = 7
    static let tileRadius: CGFloat = 7
    static let pillRadius: CGFloat = 20

    static let tileSize: CGFloat = 26
}

extension View {
    /// 发丝级分组表面：淡填充 + 1px 描边，替代 `.regularMaterial` 毛玻璃卡片。
    func shellGroupSurface(cornerRadius: CGFloat = ShellStyle.groupRadius) -> some View {
        background(ShellStyle.groupFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ShellStyle.groupStroke)
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
            .fill(isActive ? ShellStyle.accentSoft : ShellStyle.tileFill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
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
        .padding(2)
        .background(ShellStyle.groupFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ShellStyle.groupStroke)
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
