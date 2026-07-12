import Foundation
import UniformTypeIdentifiers

enum TimelineProjectFileType {
    static let identifier = "run.libo.datalayer-studio.project"
    static let filenameExtension = "dlsproj"
    static let contentType = UTType(exportedAs: identifier, conformingTo: .json)

    static var openContentTypes: [UTType] {
        [contentType, .json]
    }

    static func matches(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(filenameExtension) == .orderedSame
    }
}
