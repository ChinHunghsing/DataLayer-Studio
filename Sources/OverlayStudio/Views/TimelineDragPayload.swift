import Foundation

enum TimelineDragPayload {
    private static let activityPrefix = "datalayer.timeline.activity:"

    static func activity(assetID: String) -> String {
        activityPrefix + assetID
    }

    static func activityAssetID(from payload: String) -> String? {
        guard payload.hasPrefix(activityPrefix) else { return nil }
        let id = String(payload.dropFirst(activityPrefix.count))
        return id.isEmpty ? nil : id
    }
}
