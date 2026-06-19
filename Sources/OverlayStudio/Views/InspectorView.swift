import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @State private var expandedSections = Set(InspectorSection.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                InspectorSelectionHeader(model: model)
                Divider()
                InspectorSettingsPanel(model: model, expandedSections: $expandedSections)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
}
