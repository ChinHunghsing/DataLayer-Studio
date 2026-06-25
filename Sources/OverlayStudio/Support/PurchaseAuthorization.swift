import Foundation
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
    case allowed
    case checking
    case restricted(PurchaseRestrictionReason, detail: String?)
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
        self.state = requirementProvider().requiresVerification ? .checking : .allowed
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
            state = .allowed
            return
        }

        guard requirement.hasReceipt else {
            state = .restricted(.missingReceipt, detail: nil)
            return
        }

        state = .checking
        switch await verifier.verifyAppTransaction() {
        case .verified:
            state = .allowed
        case let .unverified(message):
            state = .restricted(.unverifiedReceipt, detail: message)
        case .unavailable:
            state = .allowed
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
