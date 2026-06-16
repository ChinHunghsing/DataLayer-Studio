import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 310)
                .background(.bar)

            Divider()

            PreviewCanvasView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            InspectorView(model: model)
                .frame(width: 330)
                .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refreshPreview()
                } label: {
                    Label("Refresh Preview", systemImage: "arrow.clockwise")
                }

                Button {
                    model.markSportStart()
                } label: {
                    Label("运动开始", systemImage: "figure.run.circle")
                }
                .disabled(model.player == nil)

                Button {
                    model.chooseOutput()
                } label: {
                    Label("Output", systemImage: "square.and.arrow.down")
                }

                Button {
                    model.export()
                } label: {
                    Label("Export", systemImage: "play.fill")
                }
                .disabled(!model.canExport || model.isExporting)
            }
        }
        .onChange(of: model.outputWidth) { _ in model.refreshPreview() }
        .onChange(of: model.outputHeight) { _ in model.refreshPreview() }
        .onChange(of: model.syncMode) { _ in model.refreshPreview() }
        .onChange(of: model.offsetSeconds) { _ in model.refreshPreview() }
        .onChange(of: model.fitStartSeconds) { _ in model.refreshPreview() }
        .onChange(of: model.syncVideoSeconds) { _ in model.refreshPreview() }
        .onChange(of: model.syncFITSeconds) { _ in model.refreshPreview() }
        .onChange(of: model.distanceUnit) { _ in model.refreshPreview() }
        .onChange(of: model.layout) { _ in model.refreshPreview() }
    }
}
