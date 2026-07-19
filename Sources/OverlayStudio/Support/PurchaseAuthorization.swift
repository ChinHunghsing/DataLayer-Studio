import Foundation
import OverlayCore
import Security
import StoreKit

struct PurchaseVerificationRequirement: Equatable {
    var applicationIdentifier: String?
    var hasReceipt: Bool

    var requiresVerification: Bool {
        applicationIdentifier != nil || hasReceipt
    }

    static func current(bundle: Bundle = .main) -> PurchaseVerificationRequirement {
        PurchaseVerificationRequirement(
            applicationIdentifier: AppStoreSigningInfo.currentApplicationIdentifier(),
            hasReceipt: AppStoreSigningInfo.hasReceipt(in: bundle)
        )
    }
}

enum PurchaseVerificationResult: Equatable {
    case verified
    case unverified(String)
    case unavailable(String)
}

enum PurchaseAuthorizationState: Equatable {
    case allowed(ExportEntitlement)
    case checking
    case restricted(PurchaseRestrictionReason, detail: String?)

    /// 导出路径使用的权益；校验中或受限时按免费层处理。
    var exportEntitlement: ExportEntitlement {
        if case let .allowed(entitlement) = self {
            return entitlement
        }
        return .free
    }
}

enum PurchaseRestrictionReason: Equatable {
    case missingReceipt
    case unverifiedReceipt
    case restoreFailed
}

protocol AppStorePurchaseVerifying {
    func verifyAppTransaction() async -> PurchaseVerificationResult
    func synchronizeAppStoreAccount() async throws
}

struct StoreKitAppStorePurchaseVerifier: AppStorePurchaseVerifying {
    func verifyAppTransaction() async -> PurchaseVerificationResult {
        do {
            let result = try await AppTransaction.shared
            switch result {
            case .verified:
                return .verified
            case let .unverified(_, error):
                return .unverified(error.localizedDescription)
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func synchronizeAppStoreAccount() async throws {
        try await AppStore.sync()
    }
}

@MainActor
final class PurchaseAuthorizationStore: ObservableObject {
    nonisolated static let fullVersionURL = URL(string: "https://apps.apple.com/cn/app/datalayer-studio/id6782545770")!

    @Published private(set) var state: PurchaseAuthorizationState

    private let requirementProvider: () -> PurchaseVerificationRequirement
    private let verifier: AppStorePurchaseVerifying
    private var hasChecked = false

    init(
        requirementProvider: @escaping () -> PurchaseVerificationRequirement = { .current() },
        verifier: AppStorePurchaseVerifying = StoreKitAppStorePurchaseVerifier()
    ) {
        self.requirementProvider = requirementProvider
        self.verifier = verifier
        // 无收据、无 App Store 签名标识的构建（GitHub 直下版/自编译版）走免费层：
        // App 全功能可用，导出叠加水印并限制 1080p。
        self.state = requirementProvider().requiresVerification ? .checking : .allowed(.free)
    }

    func verifyIfNeeded() async {
        guard !hasChecked else { return }
        await verify(force: false)
    }

    func retryVerification() async {
        await verify(force: true)
    }

    func restoreAndVerify() async {
        state = .checking
        do {
            try await verifier.synchronizeAppStoreAccount()
            await verify(force: true)
        } catch {
            state = .restricted(.restoreFailed, detail: error.localizedDescription)
        }
    }

    private func verify(force: Bool) async {
        guard force || !hasChecked else { return }
        hasChecked = true

        let requirement = requirementProvider()
        guard requirement.requiresVerification else {
            state = .allowed(.free)
            return
        }

        guard requirement.hasReceipt else {
            state = .restricted(.missingReceipt, detail: nil)
            return
        }

        state = .checking
        switch await verifier.verifyAppTransaction() {
        case .verified:
            state = .allowed(.full)
        case let .unverified(message):
            state = .restricted(.unverifiedReceipt, detail: message)
        case .unavailable:
            // 有收据说明是 App Store/TestFlight 构建；StoreKit 暂时不可用时放行全功能，避免误伤付费用户。
            state = .allowed(.full)
        }
    }
}

enum AppStoreSigningInfo {
    static func hasReceipt(in bundle: Bundle) -> Bool {
        guard let receiptURL = bundle.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }

    static func currentApplicationIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else {
            return nil
        }

        return entitlements["com.apple.application-identifier"] as? String
    }
}
