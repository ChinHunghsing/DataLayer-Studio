import SwiftUI

/// 统一整数输入行为：无千分位、失焦提交、范围夹取，可选输入中实时发布。
struct IntegerTextField: View {
    var title = ""
    var value: Int
    var range: ClosedRange<Int> = Int.min...Int.max
    var width: CGFloat? = nil
    var publishesValidDraft = false
    var set: (Int) -> Void

    @State private var draft = ""
    @State private var dragStartValue: Int?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: width)
            .focused($isFocused)
            .onSubmit(commit)
            .onAppear(perform: refresh)
            .onChange(of: draft) { _ in
                guard publishesValidDraft, isFocused,
                      let parsed = NumberTextFormatter.parseInt(draft),
                      range.contains(parsed) else { return }
                set(parsed)
            }
            .onChange(of: value) { _ in
                guard !isFocused else { return }
                refresh()
            }
            .onChange(of: isFocused) { focused in
                if focused {
                    refresh()
                } else {
                    commit()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { gesture in
                        let base = dragStartValue ?? value
                        dragStartValue = base
                        let adjusted = Self.draggedValue(
                            base: base,
                            horizontalTranslation: gesture.translation.width,
                            range: range
                        )
                        draft = NumberTextFormatter.formatInt(adjusted)
                        set(adjusted)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        refresh()
                    }
            )
    }

    private func refresh() {
        draft = NumberTextFormatter.formatInt(value)
    }

    private func commit() {
        guard let parsed = NumberTextFormatter.parseInt(draft) else {
            refresh()
            return
        }
        let clamped = min(range.upperBound, max(range.lowerBound, parsed))
        set(clamped)
        draft = NumberTextFormatter.formatInt(clamped)
    }

    static func draggedValue(
        base: Int,
        horizontalTranslation: CGFloat,
        range: ClosedRange<Int>
    ) -> Int {
        let delta = Int((horizontalTranslation / 4).rounded(.towardZero))
        let (candidate, overflow) = base.addingReportingOverflow(delta)
        if overflow {
            return delta < 0 ? range.lowerBound : range.upperBound
        }
        return min(range.upperBound, max(range.lowerBound, candidate))
    }
}
