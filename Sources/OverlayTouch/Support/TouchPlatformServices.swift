import Foundation

#if canImport(UIKit)
import UIKit

/// 导出期间保持屏幕常亮，退后台时用后台任务争取收尾窗口。
/// AVAssetWriter 无法在挂起中继续；窗口到期先触发 `onBackgroundExpiration` 取消写出，再释放后台任务。
public final class TouchExportRuntimeGuard: TouchExportRuntimeGuarding {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    public init() {}

    public func exportDidStart(onBackgroundExpiration: @escaping () -> Void) {
        UIApplication.shared.isIdleTimerDisabled = true
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "datalayer-export") { [weak self] in
            onBackgroundExpiration()
            self?.endBackgroundTask()
        }
    }

    public func exportDidEnd() {
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
#endif

#if canImport(Photos) && os(iOS)
import Photos

public enum TouchPhotoLibrarySaver {
    public static func saveVideo(at url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
#endif
