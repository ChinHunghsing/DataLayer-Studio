import XCTest
@testable import OverlayTouch

final class MobileSubscriptionStoreTests: XCTestCase {
    func testEntitlementStateAllowsSubscribedGraceAndOfflineCache() {
        let now = Date(timeIntervalSince1970: 1_000)
        let future = now.addingTimeInterval(60)
        let recentlyExpired = now.addingTimeInterval(-60)
        let stale = now.addingTimeInterval(-(MobileSubscriptionStore.offlineTolerance + 60))

        XCTAssertTrue(
            MobileSubscriptionEntitlementState.subscribed(expiry: future, inTrial: false)
                .allowsExport(cachedExpirationDate: nil, now: now)
        )
        XCTAssertTrue(
            MobileSubscriptionEntitlementState.gracePeriod
                .allowsExport(cachedExpirationDate: nil, now: now)
        )
        XCTAssertTrue(
            MobileSubscriptionEntitlementState.unknown
                .allowsExport(cachedExpirationDate: recentlyExpired, now: now)
        )
        XCTAssertFalse(
            MobileSubscriptionEntitlementState.subscribed(expiry: recentlyExpired, inTrial: false)
                .allowsExport(cachedExpirationDate: nil, now: now)
        )
        XCTAssertFalse(
            MobileSubscriptionEntitlementState.unknown
                .allowsExport(cachedExpirationDate: stale, now: now)
        )
        XCTAssertFalse(
            MobileSubscriptionEntitlementState.notSubscribed
                .allowsExport(cachedExpirationDate: future, now: now)
        )
    }

    func testExpiredVerifiedCurrentEntitlementMapsToGracePeriod() {
        XCTAssertEqual(
            MobileSubscriptionStore.verifiedCurrentEntitlementState(
                bestExpiry: nil,
                hasExpiredCurrentEntitlement: true,
                usesIntroOffer: false
            ),
            .gracePeriod
        )
        XCTAssertNil(
            MobileSubscriptionStore.verifiedCurrentEntitlementState(
                bestExpiry: nil,
                hasExpiredCurrentEntitlement: false,
                usesIntroOffer: false
            )
        )
    }
}
