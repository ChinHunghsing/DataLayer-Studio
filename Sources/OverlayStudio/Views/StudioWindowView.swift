import SwiftUI

struct StudioWindowView: View {
    @StateObject private var model = StudioModel()
    @State private var didApplyLaunchOptions = false

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1240, minHeight: 760)
            .onAppear(perform: applyLaunchOptionsIfNeeded)
    }

    private func applyLaunchOptionsIfNeeded() {
        guard !didApplyLaunchOptions else { return }
        didApplyLaunchOptions = true
        let options = StudioLaunchOptions(arguments: CommandLine.arguments)
        model.applyLaunchOptions(options)
    }
}

struct StudioLaunchOptions: Equatable {
    var videoURL: URL?
    var fitURL: URL?
    var offsetSeconds: Double?

    init(arguments: [String]) {
        var videoURL: URL?
        var fitURL: URL?
        var offsetSeconds: Double?
        var index = 0

        while index < arguments.count {
            defer { index += 1 }
            switch arguments[index] {
            case "--video":
                guard let value = arguments[safe: index + 1] else { continue }
                videoURL = URL(fileURLWithPath: value)
                index += 1
            case "--fit":
                guard let value = arguments[safe: index + 1] else { continue }
                fitURL = URL(fileURLWithPath: value)
                index += 1
            case "--offset":
                guard let value = arguments[safe: index + 1],
                      let parsed = Double(value),
                      parsed.isFinite else {
                    continue
                }
                offsetSeconds = parsed
                index += 1
            default:
                continue
            }
        }

        self.videoURL = videoURL
        self.fitURL = fitURL
        self.offsetSeconds = offsetSeconds
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
