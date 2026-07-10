import Foundation

enum TimelineDragPayload {
    private static let activityPrefix = "datalayer.timeline.activity:"
    private static let videoPrefix = "datalayer.timeline.video:"

    static func video(assetID: String) -> String {
        videoPrefix + assetID
    }

    static func videoAssetID(from payload: String) -> String? {
        assetID(from: payload, prefix: videoPrefix)
    }

    static func activity(assetID: String) -> String {
        activityPrefix + assetID
    }

    static func activityAssetID(from payload: String) -> String? {
        assetID(from: payload, prefix: activityPrefix)
    }

    private static func assetID(from payload: String, prefix: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let id = String(payload.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}
