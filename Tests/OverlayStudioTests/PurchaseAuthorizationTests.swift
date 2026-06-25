import XCTest
@testable import OverlayStudio

@MainActor
final class PurchaseAuthorizationTests: XCTestCase {
    func testVerificationIsSkippedForLocalAndDeveloperIDBuilds() async {
        let store = PurchaseAuthorizationStore(
            requirementProvider: {
                PurchaseVerificationRequirement(applicationIdentifier: nil, hasReceipt: false)
            },
            verifier: FakePurchaseVerifier(result: .unverified("should not be called"))
        )

        await store.verifyIfNeeded()

        XCTAssertEqual(store.state, .allowed)
    }

    func testAppStoreSignedBuildWithoutReceiptIsRestricted() async {
        let store = PurchaseAuthorizationStore(
            requirementProvider: {
                PurchaseVerificationRequirement(
                    applicationIdentifier: "XUQV24QYZM.run.libo.datalayer-studio",
                    hasReceipt: false
                )
            },
            verifier: FakePurchaseVerifier(result: .verified)
        )

        await store.verifyIfNeeded()

        XCTAssertEqual(store.state, .restricted(.missingReceipt, detail: nil))
    }

    func testVerifiedAppStoreReceiptAllowsLaunch() async {
        let store = PurchaseAuthorizationStore(
            requirementProvider: {
                PurchaseVerificationRequirement(
                    applicationIdentifier: "XUQV24QYZM.run.libo.datalayer-studio",
                    hasReceipt: true
                )
            },
            verifier: FakePurchaseVerifier(result: .verified)
        )

        await store.verifyIfNeeded()

        XCTAssertEqual(store.state, .allowed)
    }

    func testTemporaryStoreKitFailureDoesNotBlockLaunch() async {
        let store = PurchaseAuthorizationStore(
            requirementProvider: {
                PurchaseVerificationRequirement(
                    applicationIdentifier: "XUQV24QYZM.run.libo.datalayer-studio",
                    hasReceipt: true
                )
            },
            verifier: FakePurchaseVerifier(result: .unavailable("storekit unavailable"))
        )

        await store.verifyIfNeeded()

        XCTAssertEqual(store.state, .allowed)
    }

    func testRestoreRechecksReceiptBeforeAllowingLaunch() async {
        var hasReceipt = false
        let store = PurchaseAuthorizationStore(
            requirementProvider: {
                PurchaseVerificationRequirement(
                    applicationIdentifier: "XUQV24QYZM.run.libo.datalayer-studio",
                    hasReceipt: hasReceipt
                )
            },
            verifier: FakePurchaseVerifier(
                result: .verified,
                synchronize: {
                    hasReceipt = true
                }
            )
        )

        await store.verifyIfNeeded()
        XCTAssertEqual(store.state, .restricted(.missingReceipt, detail: nil))

        await store.restoreAndVerify()
        XCTAssertEqual(store.state, .allowed)
    }
}

private struct FakePurchaseVerifier: AppStorePurchaseVerifying {
    var result: PurchaseVerificationResult
    var synchronize: () async throws -> Void = {}

    func verifyAppTransaction() async -> PurchaseVerificationResult {
        result
    }

    func synchronizeAppStoreAccount() async throws {
        try await synchronize()
    }
}
