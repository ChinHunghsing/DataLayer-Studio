import Foundation
import UniformTypeIdentifiers

/// Collects file URLs from Finder drop providers for the media pool and timeline lanes.
enum MediaFileDrop {
    static func hasFileURLs(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    }

    /// Load every dropped file URL, preserving provider order, and deliver the result on the
    /// main queue. Returns false when no provider carries a file URL.
    @discardableResult
    static func loadURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) -> Bool {
        let urlProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !urlProviders.isEmpty else { return false }

        let collector = DispatchQueue(label: "studio.mediaFileDrop.collector")
        let group = DispatchGroup()
        var orderedURLs = [URL?](repeating: nil, count: urlProviders.count)
        for (index, provider) in urlProviders.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                collector.async {
                    orderedURLs[index] = url
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            completion(orderedURLs.compactMap { $0 })
        }
        return true
    }
}
