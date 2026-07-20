import Foundation
import StoreKit

#if os(iOS)
import UIKit
#endif

public enum MobileSubscriptionEntitlementState: Equatable {
    case unknown
    case subscribed(expiry: Date?, inTrial: Bool)
    case gracePeriod
    case notSubscribed

    public func allowsExport(cachedExpirationDate: Date?, now: Date) -> Bool {
        switch self {
        case .unknown:
            return Self.cachedEntitlementAllowsExport(expirationDate: cachedExpirationDate, now: now)
        case let .subscribed(expiry, _):
            guard let expiry else { return true }
            return expiry > now
        case .gracePeriod:
            return true
        case .notSubscribed:
            return false
        }
    }

    public static func cachedEntitlementAllowsExport(expirationDate: Date?, now: Date) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate.addingTimeInterval(MobileSubscriptionStore.offlineTolerance) > now
    }
}

@MainActor
public final class MobileSubscriptionStore: ObservableObject, SubscriptionEntitlementProviding {
    nonisolated public static let yearlyProductID = "run.libo.datalayerstudio.mobile.yearly"
    nonisolated public static let monthlyProductID = "run.libo.datalayerstudio.mobile.monthly"
    nonisolated public static let productIDs = [yearlyProductID, monthlyProductID]
    nonisolated public static let offlineTolerance: TimeInterval = 24 * 60 * 60
    nonisolated public static let standardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    nonisolated public static let privacyURL = URL(string: "https://github.com/leeeboo/DataLayer-Studio/blob/main/PRIVACY.md")!

    private static let cachedExpirationKey = "run.libo.datalayer-studio.mobile.subscription.expiration"

    @Published public private(set) var state: MobileSubscriptionEntitlementState = .unknown
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var isLoadingProducts = false
    @Published public private(set) var isEligibleForIntroOffer = false
    @Published public private(set) var lastMessage: TouchMessage?

    private let defaults: UserDefaults
    private let now: () -> Date
    private var updatesTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var productLoadFailed = false

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
    }

    deinit {
        updatesTask?.cancel()
        refreshTask?.cancel()
    }

    public var hasActiveExportEntitlement: Bool {
        state.allowsExport(cachedExpirationDate: cachedExpirationDate, now: now())
    }

    public var stateMessage: TouchMessage {
        switch state {
        case .unknown:
            return TouchMessage(hasActiveExportEntitlement ? "subscription.state.active" : "subscription.state.unknown")
        case let .subscribed(_, inTrial):
            return TouchMessage(inTrial ? "subscription.state.trial" : "subscription.state.active")
        case .gracePeriod:
            return TouchMessage("subscription.state.gracePeriod")
        case .notSubscribed:
            return TouchMessage("subscription.state.none")
        }
    }

    public func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.refreshEntitlements()
                // 续订、Offer Code 兑换与 StoreKit 视图发起的购买都经由该流到达；
                // 权益已按 currentEntitlements 刷新，必须 finish，否则每次启动重投未完成交易。
                if case let .verified(transaction) = result {
                    await transaction.finish()
                }
            }
        }
        refreshTask = Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    public func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { lhs, rhs in
                (Self.productIDs.firstIndex(of: lhs.id) ?? .max) < (Self.productIDs.firstIndex(of: rhs.id) ?? .max)
            }
            isEligibleForIntroOffer = await products.first?.subscription?.isEligibleForIntroOffer ?? false
            productLoadFailed = false
        } catch {
            productLoadFailed = true
            lastMessage = TouchMessage("subscription.error", [error.localizedDescription])
        }
    }

    public func refreshEntitlements() async {
        if let graceState = await currentGracePeriodState() {
            state = graceState
            return
        }

        var bestExpiry: Date?
        var usesIntroOffer = false
        var hasExpiredCurrentEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.revocationDate == nil,
                  Self.productIDs.contains(transaction.productID) else {
                continue
            }
            if let expirationDate = transaction.expirationDate, expirationDate <= now() {
                hasExpiredCurrentEntitlement = true
                continue
            }
            if let expirationDate = transaction.expirationDate,
               bestExpiry.map({ expirationDate > $0 }) ?? true {
                bestExpiry = expirationDate
            }
            if transaction.offerType == .introductory {
                usesIntroOffer = true
            }
        }

        if let verifiedState = Self.verifiedCurrentEntitlementState(
            bestExpiry: bestExpiry,
            hasExpiredCurrentEntitlement: hasExpiredCurrentEntitlement,
            usesIntroOffer: usesIntroOffer
        ) {
            if case let .subscribed(expiry?, _) = verifiedState {
                cacheExpirationDate(expiry)
            }
            state = verifiedState
        } else if productLoadFailed,
                  MobileSubscriptionEntitlementState.cachedEntitlementAllowsExport(
                    expirationDate: cachedExpirationDate,
                    now: now()
                  ) {
            state = .unknown
        } else {
            state = .notSubscribed
        }
    }

    public func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                if case let .verified(transaction) = verification {
                    await transaction.finish()
                }
                await refreshEntitlements()
            case .pending:
                lastMessage = TouchMessage("subscription.pending")
            case .userCancelled:
                break
            @unknown default:
                await refreshEntitlements()
            }
        } catch {
            lastMessage = TouchMessage("subscription.error", [error.localizedDescription])
        }
    }

    public func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastMessage = TouchMessage("subscription.restored")
        } catch {
            lastMessage = TouchMessage("subscription.error", [error.localizedDescription])
        }
    }

    #if os(iOS)
    public func showManageSubscriptions() async {
        guard let scene = foregroundWindowScene else { return }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            lastMessage = TouchMessage("subscription.error", [error.localizedDescription])
        }
    }

    public func redeemOfferCode() async {
        guard let scene = foregroundWindowScene else { return }
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            await refreshEntitlements()
        } catch {
            lastMessage = TouchMessage("subscription.error", [error.localizedDescription])
        }
    }

    private var foregroundWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
    #endif

    private var cachedExpirationDate: Date? {
        let timestamp = defaults.double(forKey: Self.cachedExpirationKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func cacheExpirationDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.cachedExpirationKey)
    }

    nonisolated static func verifiedCurrentEntitlementState(
        bestExpiry: Date?,
        hasExpiredCurrentEntitlement: Bool,
        usesIntroOffer: Bool
    ) -> MobileSubscriptionEntitlementState? {
        if let bestExpiry {
            return .subscribed(expiry: bestExpiry, inTrial: usesIntroOffer)
        }
        // `currentEntitlements` only yields subscriptions that still confer service;
        // an expired verified transaction here is therefore in billing grace period.
        return hasExpiredCurrentEntitlement ? .gracePeriod : nil
    }

    private func currentGracePeriodState() async -> MobileSubscriptionEntitlementState? {
        for product in products {
            guard let subscription = product.subscription,
                  let statuses = try? await subscription.status else {
                continue
            }
            for status in statuses where status.state == .inGracePeriod {
                guard case let .verified(transaction) = status.transaction,
                      transaction.revocationDate == nil,
                      Self.productIDs.contains(transaction.productID) else {
                    continue
                }
                return .gracePeriod
            }
        }
        return nil
    }
}
