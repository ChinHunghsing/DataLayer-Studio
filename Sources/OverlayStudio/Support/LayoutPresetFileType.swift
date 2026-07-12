import Foundation
import UniformTypeIdentifiers

enum LayoutPresetFileType {
    static let identifier = "run.libo.datalayer-studio.layout-preset"
    static let filenameExtension = "dlspreset"
    static let contentType = UTType(exportedAs: identifier, conformingTo: .json)

    static var importContentTypes: [UTType] {
        [contentType, .json]
    }

    static func matches(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(filenameExtension) == .orderedSame
    }
}
